defmodule Notebook.BotsTest do
  # SQLite takes one writer at a time: these write a lot, so they run alone.
  use Notebook.DataCase, async: false
  use Oban.Testing, repo: Notebook.Repo, engine: Oban.Engines.Lite

  import Notebook.AccountsFixtures

  alias Notebook.Accounts.Scope
  alias Notebook.Bots
  alias Notebook.Bots.{Bot, Run, Worker}
  alias Notebook.{Collaboration, Pages, Publishing, Repo, Spaces}

  setup do
    hanzo =
      user_fixture(%{name: "Hattori Hanzo"})
      |> Ecto.Changeset.change(admin: true)
      |> Repo.update!()

    yuki = user_fixture(%{name: "Yuki Hattori"})
    admin = Scope.for_user(hanzo)
    {:ok, forge} = Spaces.create_team(admin, %{name: "The forge"})

    {:ok, page} =
      Pages.create(admin, %{
        "title" => "The last blade",
        "space_id" => forge.id,
        "body" => Kotoba.Content.from_markdown("Folded twelve times, quenched at dawn.")
      })

    :ok = Bots.put_api_key(admin, "sk-ant-test")
    on_exit(fn -> Notebook.Secrets.delete("anthropic.api_key") end)

    %{hanzo: hanzo, yuki: yuki, admin: admin, forge: forge, page: page}
  end

  defp bot!(admin, forge, attrs \\ %{}) do
    {:ok, bot} =
      Bots.create(
        admin,
        Map.merge(
          %{"name" => "Gardener", "instructions" => "Tidy the tags.", "tools" => ["comment"]},
          attrs
        )
      )

    {:ok, _} = Bots.set_role(admin, bot, forge, "commenter")
    bot
  end

  # The Claude API, as the test says it answers: each request to the next
  # answer, kept to look at.
  defp claude(answers) do
    {:ok, agent} = Agent.start_link(fn -> {answers, []} end)

    Req.Test.stub(Bots.Claude, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      answer =
        Agent.get_and_update(agent, fn {[next | rest], seen} ->
          {next, {rest, seen ++ [{JSON.decode!(body), conn.req_headers}]}}
        end)

      Req.Test.json(conn, answer)
    end)

    agent
  end

  defp seen(agent), do: agent |> Agent.get(& &1) |> elem(1)

  defp answer(content, stop \\ "end_turn"),
    do: %{
      "content" => content,
      "stop_reason" => stop,
      "usage" => %{"input_tokens" => 1_000, "output_tokens" => 100}
    }

  defp eventually(fun, tries \\ 100) do
    case fun.() do
      falsy when falsy in [nil, false, []] and tries > 0 ->
        Process.sleep(10)
        eventually(fun, tries - 1)

      result ->
        result
    end
  end

  describe "admins make bots" do
    test "a bot has an account no one signs in to, and is in no list of people", %{
      admin: admin,
      yuki: yuki,
      forge: forge
    } do
      bot = bot!(admin, forge)
      assert %{bot: true, name: "Gardener"} = bot.user
      refute Notebook.Accounts.get_user_by_email_and_password(bot.user.email, "")
      refute bot.user.id in Enum.map(Notebook.Accounts.list_users(), & &1.id)
      refute bot.user.id in Enum.map(Spaces.outsiders(forge), & &1.id)

      assert {:error, :forbidden} = Bots.create(Scope.for_user(yuki), %{"name" => "Mine"})
      assert [] = Bots.list(Scope.for_user(yuki))
      assert [%Bot{name: "Gardener"}] = Bots.list(admin)

      {:ok, renamed} = Bots.update(admin, bot, %{"name" => "Librarian"})
      assert renamed.user.name == "Librarian"

      {:ok, _} = Bots.delete(admin, renamed)
      refute Repo.get(Bot, bot.id)
      refute Repo.get(Notebook.Accounts.User, bot.user.id)
    end

    test "a bot, like an agent or a visitor, does not run what only a person runs" do
      person = Issho.Identity.new(%{id: "1", name: "Hanzo"})
      bot = Issho.Identity.new(%{id: "bot:1", name: "Docs", kind: :service})
      guest = Issho.Identity.new(%{id: "guest:abc", name: "A visitor", kind: :guest})

      for action <- Notebook.Actions.people() do
        assert action.authorize(%{}, person) == :ok
        assert {:error, _} = action.authorize(%{}, bot)
        assert {:error, _} = action.authorize(%{}, guest)
      end
    end

    test "every tool an agent has is in a group, but a person's agent's memory" do
      grouped = Bots.tool_groups() |> Enum.flat_map(&elem(&1, 3)) |> MapSet.new()
      names = Notebook.Tools.all() |> Enum.map(& &1.name()) |> MapSet.new()

      assert MapSet.difference(names, grouped) |> Enum.sort() == ["memory"]
      assert MapSet.subset?(grouped, names)
    end

    test "its tools are its groups', reading always; a schedule needs its task", %{
      admin: admin,
      forge: forge
    } do
      bot = bot!(admin, forge)
      names = Bots.tool_names(bot)
      assert "read_text" in names and "comment" in names
      refute "type_text" in names
      refute "memory" in names

      assert {:error, changeset} =
               Bots.create(admin, %{"name" => "Clock", "schedule" => "FREQ=DAILY@09:00"})

      assert %{schedule_task: [_]} = errors_on(changeset)
      assert {:error, changeset} = Bots.create(admin, %{"name" => "Clock", "schedule" => "daily"})
      assert %{schedule: [_]} = errors_on(changeset)
      assert {:error, changeset} = Bots.create(admin, %{"name" => "X", "tools" => ["fly"]})
      assert %{tools: [_]} = errors_on(changeset)
    end
  end

  describe "in the rooms" do
    test "a bot does what its role lets it, as an agent, while it is on", %{
      admin: admin,
      forge: forge,
      page: page
    } do
      bot = bot!(admin, forge)
      identity = Issho.Identity.new(Bots.actor(bot))
      room = Collaboration.room(page)

      assert :ok = Collaboration.authorize(identity, room, :read)
      assert :ok = Collaboration.authorize(identity, room, :comment)
      assert {:error, :forbidden} = Collaboration.authorize(identity, room, :write)

      {:ok, _} = Pages.set_closed_to_agents(admin, page, true)
      assert {:error, :forbidden} = Collaboration.authorize(identity, room, :read)
      {:ok, page} = Pages.set_closed_to_agents(admin, page, false)

      {:ok, _} = Bots.update(admin, bot, %{"enabled" => false})

      assert {:error, :forbidden} =
               Collaboration.authorize(identity, Collaboration.room(page), :read)
    end

    test "an agent or a bot hands a task to a bot that takes them", %{
      admin: admin,
      forge: forge,
      page: page
    } do
      bot = bot!(admin, forge)
      other = bot!(admin, forge, %{"name" => "Scribe"})
      room = Collaboration.room(page)
      from = Issho.Identity.new(Bots.actor(other))

      assert :ok = Collaboration.hand_off(from, room, Bots.key(bot))
      assert {:error, :forbidden} = Collaboration.hand_off(from, room, "bot:999999")

      person = Issho.Identity.new(%{id: "1", name: "Someone"})
      assert {:error, :forbidden} = Collaboration.hand_off(person, room, Bots.key(bot))

      {:ok, _} = Bots.update(admin, bot, %{"on_mention" => false})
      assert {:error, :forbidden} = Collaboration.hand_off(from, room, Bots.key(bot))
    end
  end

  describe "what wakes a bot" do
    test "a mention in a comment, through its inbox", %{
      admin: admin,
      forge: forge,
      page: page,
      hanzo: hanzo
    } do
      bot = bot!(admin, forge)

      {:ok, %{thread: thread}} =
        Issho.Comments.start(
          Notebook.Issho,
          Collaboration.room(page),
          %{id: to_string(hanzo.id), name: "Hattori Hanzo"},
          nil,
          "Gardener, tidy this page's tags",
          mentions: [Bots.key(bot)]
        )

      assert [job] = eventually(fn -> all_enqueued(worker: Worker) end)
      assert %{"bot_id" => id, "trigger" => %{"kind" => "inbox", "item" => item}} = job.args
      assert id == bot.id
      assert %{"name" => "comment.created", "data" => %{"thread" => ^thread}} = item
    end

    test "a new page in a space it reads, when it takes new pages, not one a bot made", %{
      admin: admin,
      forge: forge
    } do
      bot = bot!(admin, forge, %{"on_new_page" => true})
      {:ok, page} = Pages.create(admin, %{"title" => "Notes", "space_id" => forge.id})

      assert_enqueued(
        worker: Worker,
        args: %{"bot_id" => bot.id, "trigger" => %{"kind" => "new_page", "page_id" => page.id}}
      )

      {:ok, _} = Bots.set_role(admin, bot, forge, "editor")
      {:ok, _} = Pages.create(Bots.scope(bot), %{"title" => "By the bot", "space_id" => forge.id})
      assert length(all_enqueued(worker: Worker)) == 1
    end

    test "its schedule: the next time is set, and when it comes the bot runs", %{
      admin: admin,
      forge: forge
    } do
      bot =
        bot!(admin, forge, %{
          "schedule" => "FREQ=DAILY@09:00",
          "schedule_task" => "Sum up yesterday's pages."
        })

      assert %DateTime{} = bot.next_run_at
      assert DateTime.compare(bot.next_run_at, DateTime.utc_now()) == :gt
      assert Bots.describe_schedule(bot) =~ "09:00"

      Bots.due(DateTime.add(bot.next_run_at, 60))

      assert_enqueued(
        worker: Worker,
        args: %{"bot_id" => bot.id, "trigger" => %{"kind" => "schedule"}}
      )

      later = Repo.get!(Bot, bot.id).next_run_at
      assert DateTime.diff(later, bot.next_run_at, :hour) == 24
    end
  end

  describe "a run" do
    test "the model's tool uses run as the bot, with its tools only, and the run counts its cost",
         %{
           admin: admin,
           forge: forge,
           page: page
         } do
      bot = bot!(admin, forge)
      room = Collaboration.room(page)

      agent =
        claude([
          answer(
            [
              %{"type" => "text", "text" => "I read it first."},
              %{
                "type" => "tool_use",
                "id" => "t1",
                "name" => "read_text",
                "input" => %{"document" => room <> "/body"}
              },
              %{
                "type" => "tool_use",
                "id" => "t2",
                "name" => "type_text",
                "input" => %{"document" => room <> "/body", "text" => "x"}
              }
            ],
            "tool_use"
          ),
          answer([%{"type" => "text", "text" => "The page reads well; nothing to tidy."}])
        ])

      :ok = perform_job(Worker, %{"bot_id" => bot.id, "trigger" => %{"kind" => "schedule"}})

      assert [%Run{status: "done", steps: 2, input_tokens: 2_000, output_tokens: 200} = run] =
               Bots.runs(bot)

      assert run.summary == "The page reads well; nothing to tidy."
      # 2 000 input tokens at $4 a million, 200 output at $20: 0.012 dollars.
      assert run.cost_micros == 12_000
      assert Bots.spent_micros(bot) == 12_000

      [{first, headers}, {second, _}] = seen(agent)
      assert {"x-api-key", "sk-ant-test"} in headers
      assert {"anthropic-version", "2026-10-21"} in headers
      assert first["model"] == "claude-opus-5-5"
      assert first["fallbacks"] == "default"
      assert first["output_config"] == %{"effort" => "medium"}
      assert first["system"] =~ "You are Gardener" and first["system"] =~ "Tidy the tags."
      [%{"content" => trigger}] = first["messages"]
      assert trigger =~ "scheduled task"

      tools = Enum.map(first["tools"], & &1["name"])
      assert "comment" in tools and "read_text" in tools
      refute "type_text" in tools

      [_user, _assistant, %{"role" => "user", "content" => [read, typed]}] = second["messages"]
      assert %{"tool_use_id" => "t1", "content" => text} = read
      assert text =~ "Folded twelve times"

      assert %{
               "tool_use_id" => "t2",
               "is_error" => true,
               "content" => "There is no tool \"type_text\"."
             } = typed
    end

    test "a bot off, past its budget, or without a key does not run", %{
      admin: admin,
      forge: forge
    } do
      bot = bot!(admin, forge, %{"monthly_budget_cents" => 1})
      Repo.insert!(%Run{bot_id: bot.id, trigger: "schedule", status: "done", cost_micros: 20_000})
      :ok = perform_job(Worker, %{"bot_id" => bot.id, "trigger" => %{"kind" => "schedule"}})
      assert [%Run{status: "stopped", error: "It spent its month's budget."} | _] = Bots.runs(bot)

      other = bot!(admin, forge, %{"name" => "Scribe"})
      :ok = Bots.put_api_key(admin, "")
      :ok = perform_job(Worker, %{"bot_id" => other.id, "trigger" => %{"kind" => "schedule"}})

      assert [%Run{status: "failed", error: "The notebook has no key of the Claude API."}] =
               Bots.runs(other)
    end

    test "a refusal ends the run, saying why", %{admin: admin, forge: forge} do
      bot = bot!(admin, forge)

      claude([
        %{
          "content" => [],
          "stop_reason" => "refusal",
          "stop_details" => %{"category" => "cyber"},
          "usage" => %{}
        }
      ])

      :ok = perform_job(Worker, %{"bot_id" => bot.id, "trigger" => %{"kind" => "schedule"}})
      assert [%Run{status: "failed", error: "The model declined: cyber"}] = Bots.runs(bot)
    end
  end

  describe "visitors" do
    setup %{admin: admin, forge: forge, page: page} do
      {:ok, page} = Publishing.publish(admin, page)
      on_exit(fn -> Application.delete_env(:notebook, :publishing) end)
      bot = bot!(admin, forge, %{"name" => "Docs", "public" => true, "on_mention" => false})
      {:ok, _} = Bots.set_role(admin, bot, forge, "viewer")
      %{page: page, bot: bot}
    end

    test "a visitor asks a bot that answers visitors, and the answer comes back", %{
      page: page,
      bot: bot
    } do
      guest = Issho.Guests.new()
      assert [%Bot{name: "Docs"}] = Bots.public_for(page)
      assert {:ok, request} = Bots.ask_public(page, bot, guest, "How many folds?")

      assert [job] = eventually(fn -> all_enqueued(worker: Worker) end)

      assert %{"kind" => "visitor", "request" => ^request, "text" => "How many folds?"} =
               job.args["trigger"]

      claude([answer([%{"type" => "text", "text" => "Twelve."}])])
      :ok = perform_job(Worker, job.args)
      assert_received {:bot_answer, ^request, "Twelve."}
    end

    test "only a bot that answers visitors, on a published page; and not too often", %{
      admin: admin,
      forge: forge,
      page: page,
      bot: bot
    } do
      guest = Issho.Guests.new()
      private = bot!(admin, forge, %{"name" => "Inside"})
      assert {:error, :forbidden} = Bots.ask_public(page, private, guest, "Hi")

      for _ <- 1..10, do: assert({:ok, _} = Bots.ask_public(page, bot, guest, "Again"))
      assert {:error, :too_many} = Bots.ask_public(page, bot, guest, "Again")

      {:ok, unpublished} = Pages.create(admin, %{"title" => "Draft", "space_id" => forge.id})
      assert {:error, :forbidden} = Bots.ask_public(unpublished, bot, Issho.Guests.new(), "Hi")
    end
  end
end
