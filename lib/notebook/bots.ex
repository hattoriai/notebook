defmodule Notebook.Bots do
  @moduledoc """
  The notebook's own bots, which its admins make and set up: a name, what
  each is told, the model it thinks with, the tools it may use, what wakes
  it and the most it may spend a month. The notebook comes with none.

  A bot works as itself, for no one: in a page's room it is
  `"bot:<id>"`, an `Issho` actor of kind `:service`, seen by its name, and
  paused or stopped as any agent. Its rights are its account's (`user`,
  `bot: true`, which no one signs in to): it may do in a space what its
  role there lets it (`set_role/4`), never on pages and spaces off limits
  to agents. Its tools are narrower still: only those of its groups
  (`tool_groups/0`), whatever its role lets it (`Issho.Tool.Context`'s
  `:only`).

  What wakes it (`Notebook.Bots.Worker` runs it, on the Claude API, with
  `Notebook.Bots.Runner`):

    * someone mentions it in a comment, or an agent hands it a task
      (`Issho.Handoffs`), or a person asks it privately: its inbox wakes it
      (`wake/2`, the instance's `:on_mention`), when it takes mentions;
    * a visitor asks it on a published page (`ask_public/4`), when it
      answers visitors;
    * a page is made in a space it reads (`page_created/1`), when it takes
      new pages;
    * its schedule comes (`due/1`, each minute).

  What it may spend is counted by its runs (`Notebook.Bots.Run`), at the
  model's list prices: past its month's budget, it does not run.
  """
  import Ecto.Query

  alias Notebook.Accounts.{Scope, User}
  alias Notebook.Bots.{Bot, Run, Schedule}
  alias Notebook.Spaces.{Member, Space}
  alias Notebook.{Permissions, Repo}

  @secret "anthropic.api_key"

  @tool_groups [
    {"read", "Read",
     "Find and read pages, texts, boards, tables, databases and charts, and the threads. Always on.",
     ~w(list_pages read_database join_room look_around read_document list_threads wait_for_events
        inbox list_actions leave_room read_text copy_text read_canvas read_grid read_chart
        set_status start_task progress finish_task point point_at)},
    {"comment", "Comment", "Write and resolve comments.", ~w(comment resolve_thread)},
    {"suggest", "Suggest",
     "Suggest text for people to take or leave, and write long answers as they come.",
     ~w(suggest_text start_stream append_to_stream finish_stream)},
    {"hand_off", "Hand off",
     "Hand tasks to other agents and bots, and answer those handed to it.",
     ~w(hand_off answer_handoff)},
    {"write", "Write texts", "Type, replace, delete, format and attach in texts.",
     ~w(select_text type_text replace_text delete_text format_text link_text add_block move_block
        paste_text attach_file)},
    {"boards", "Change boards", "Add, move, connect, change and delete on boards.",
     ~w(add_node move_node connect_nodes update_node delete_items draw_on_canvas draw_shape add_image
        change_document update_state)},
    {"tables", "Change tables and databases",
     "Edit cells, add, move and delete rows and records, add fields and views, change charts.",
     ~w(select_cells edit_cells add_rows delete_rows add_records update_records delete_records
        move_record add_field add_view change_chart)},
    {"pages", "Make and arrange pages",
     "Make pages, rename and move them, set their due dates, archive and restore them.",
     ~w(create_page rename_page set_due_date move_page archive_page restore_page click navigate)}
  ]

  # The models' list prices, in dollars a million tokens: input, output and
  # cache reads (cache writes are 1.25 input).
  @prices %{
    "claude-opus-5-5" => {4.0, 20.0, 0.20},
    "claude-sonnet-5-5" => {2.0, 10.0, 0.20},
    "claude-haiku-5-5" => {0.10, 0.50, 0.01},
    "claude-fable-5-1" => {10.0, 50.0, 0.25}
  }

  @doc "The groups of tools a bot is given: `{name, label, description, tools}`."
  def tool_groups, do: @tool_groups

  @doc "The names of the groups of tools."
  def tool_group_names, do: Enum.map(@tool_groups, &elem(&1, 0))

  @doc "The names of the tools a bot may use: those of its groups, and reading always."
  def tool_names(%Bot{tools: groups}) do
    groups = Enum.uniq(["read" | groups || []])

    for {group, _label, _description, tools} <- @tool_groups,
        group in groups,
        tool <- tools,
        do: tool
  end

  @doc "The key of a bot in the rooms."
  def key(%Bot{id: id}), do: "bot:#{id}"

  @doc "A bot as an actor of the rooms: itself, for no one."
  def actor(%Bot{} = bot), do: %{id: key(bot), name: bot.name, kind: :service}

  @doc "The bot of a key of the rooms, with its account, or nil."
  def by_key("bot:" <> id) do
    case Integer.parse(id) do
      {id, ""} -> Bot |> Repo.get(id) |> Repo.preload(:user)
      _ -> nil
    end
  end

  def by_key(_key), do: nil

  @doc "The scope a bot works with: its account's, as an agent's (not on what is off limits to agents)."
  def scope(%Bot{} = bot), do: Scope.for_agent(Repo.preload(bot, :user).user, key(bot))

  ## Admins make and set up bots

  @doc "The notebook's bots, by name: its admins see them."
  def list(scope) do
    if Scope.admin?(scope),
      do: Repo.all(from b in Bot, order_by: b.name, preload: :user),
      else: []
  end

  @doc "The bots that answer visitors on a published page: enabled, and reading its space."
  def public_for(%Notebook.Pages.Page{} = page) do
    from(b in Bot, where: b.public and b.enabled, preload: :user, order_by: b.name)
    |> Repo.all()
    |> Enum.filter(&Permissions.allowed?(scope(&1), :read, page))
  end

  @doc "The bots someone may mention on a page: enabled, taking mentions, and reading it."
  def mentionable(%Notebook.Pages.Page{} = page) do
    from(b in Bot, where: b.enabled and b.on_mention, preload: :user, order_by: b.name)
    |> Repo.all()
    |> Enum.filter(&Permissions.allowed?(scope(&1), :read, page))
  end

  @doc "A bot, for its admins."
  def get!(scope, id) do
    true = Scope.admin?(scope)
    Repo.get!(Bot, id) |> Repo.preload(:user)
  end

  @doc "A bot's changes, for a form."
  def change(%Bot{} = bot, attrs \\ %{}), do: Bot.changeset(bot, attrs)

  @doc """
  Makes a bot, with its account: an admin may. It is in no space until an
  admin gives it a role in one (`set_role/4`).
  """
  def create(scope, attrs) do
    with :ok <- admin(scope) do
      changeset = Bot.changeset(%Bot{}, attrs)

      Repo.transact(fn ->
        with {:ok, bot} <- Ecto.Changeset.apply_action(changeset, :insert),
             {:ok, user} <- Repo.insert(account(bot.name)),
             {:ok, bot} <-
               changeset
               |> Ecto.Changeset.put_change(:user_id, user.id)
               |> Ecto.Changeset.put_change(:next_run_at, next_run(bot.schedule))
               |> Repo.insert() do
          {:ok, %{bot | user: user}}
        end
      end)
    end
  end

  defp account(name) do
    %User{
      name: name,
      email: "bot-#{Ecto.UUID.generate()}@bots.notebook.invalid",
      bot: true,
      confirmed_at: DateTime.utc_now(:second)
    }
  end

  @doc "Changes a bot (an admin may): its account's name follows."
  def update(scope, %Bot{} = bot, attrs) do
    with :ok <- admin(scope) do
      changeset = Bot.changeset(bot, attrs)

      Repo.transact(fn ->
        with {:ok, updated} <- Ecto.Changeset.apply_action(changeset, :update),
             changeset =
               Ecto.Changeset.put_change(changeset, :next_run_at, next_run(updated.schedule)),
             {:ok, updated} <- Repo.update(changeset),
             bot = Repo.preload(bot, :user),
             {:ok, user} <- bot.user |> Ecto.Changeset.change(name: updated.name) |> Repo.update() do
          {:ok, %{updated | user: user}}
        end
      end)
    end
  end

  @doc "Deletes a bot, its account, its roles and its runs (an admin may)."
  def delete(scope, %Bot{} = bot) do
    with :ok <- admin(scope) do
      bot = Repo.preload(bot, :user)
      Repo.delete(bot.user)
      Permissions.changed()
      {:ok, bot}
    end
  end

  defp admin(scope), do: if(Scope.admin?(scope), do: :ok, else: {:error, :forbidden})

  ## Its spaces

  @doc "The spaces a bot may have a role in (General and the teams), each with its role or nil."
  def spaces(%Bot{} = bot) do
    roles =
      from(m in Member, where: m.user_id == ^bot.user_id, select: {m.space_id, m.role})
      |> Repo.all()
      |> Map.new()

    from(s in Space,
      where: s.kind in ["general", "team"],
      order_by: [s.kind != "general", s.name]
    )
    |> Repo.all()
    |> Enum.map(&{&1, Map.get(roles, &1.id)})
  end

  @doc """
  Gives a bot a role in a space (General or a team), `viewer`, `commenter`
  or `editor`, or none (nil): an admin may.
  """
  def set_role(scope, %Bot{} = bot, %Space{kind: kind} = space, role)
      when kind in ["general", "team"] and role in [nil, "viewer", "commenter", "editor"] do
    with :ok <- admin(scope) do
      existing = Repo.get_by(Member, space_id: space.id, user_id: bot.user_id)

      result =
        case {existing, role} do
          {nil, nil} ->
            {:ok, nil}

          {nil, role} ->
            Repo.insert(%Member{space_id: space.id, user_id: bot.user_id, role: role})

          {member, nil} ->
            Repo.delete(member)

          {member, role} ->
            member |> Ecto.Changeset.change(role: role) |> Repo.update()
        end

      Permissions.changed()
      result
    end
  end

  def set_role(_scope, _bot, _space, _role), do: {:error, :invalid}

  ## What it spends

  @doc "A bot's runs, newest first."
  def runs(%Bot{id: id}, limit \\ 20),
    do: Repo.all(from r in Run, where: r.bot_id == ^id, order_by: [desc: r.id], limit: ^limit)

  @doc "What a bot spent this month, in millionths of a dollar."
  def spent_micros(%Bot{id: id}, now \\ DateTime.utc_now()) do
    start = DateTime.new!(Date.beginning_of_month(DateTime.to_date(now)), ~T[00:00:00])

    from(r in Run, where: r.bot_id == ^id and r.inserted_at >= ^start, select: sum(r.cost_micros))
    |> Repo.one()
    |> Kernel.||(0)
  end

  @doc "Whether a bot has spent its month's budget."
  def over_budget?(%Bot{} = bot), do: spent_micros(bot) >= bot.monthly_budget_cents * 10_000

  @doc """
  What tokens cost on a model, in millionths of a dollar: a usage of the
  Messages API (`input_tokens`, `output_tokens`, the cache's).
  """
  def cost_micros(model, usage) do
    {input, output, cache_read} = Map.get(@prices, model, @prices["claude-opus-5-5"])

    round(
      (usage["input_tokens"] || 0) * input + (usage["output_tokens"] || 0) * output +
        (usage["cache_creation_input_tokens"] || 0) * input * 1.25 +
        (usage["cache_read_input_tokens"] || 0) * cache_read
    )
  end

  ## The Claude API's key

  @doc "Whether the notebook has a key of the Claude API, for its bots."
  def api_key?, do: api_key() != nil

  @doc false
  def api_key, do: Notebook.Secrets.get(@secret)

  @doc "Keeps the Claude API's key (an admin may), encrypted with the notebook's secrets."
  def put_api_key(scope, key) when is_binary(key) do
    with :ok <- admin(scope) do
      case String.trim(key) do
        "" -> Notebook.Secrets.delete(@secret)
        key -> Notebook.Secrets.put(@secret, key)
      end
    end
  end

  ## What wakes a bot

  @doc """
  A bot's inbox has something new (the Issho instance's `:on_mention`): a
  mention in a comment, a task handed to it, a person asking it, when the
  bot takes mentions; a visitor asking it on a published page, when it
  answers visitors. Its run is a job.
  """
  def wake("bot:" <> _ = key, %{} = item) do
    with %Bot{enabled: true} = bot <- by_key(key) do
      cond do
        visitor?(item) -> if bot.public, do: enqueue(bot, visitor(item))
        bot.on_mention -> enqueue(bot, %{"kind" => "inbox", "item" => item})
        true -> :ok
      end
    end

    :ok
  end

  def wake(_key, _item), do: :ok

  # A visitor's question on a published page (Issho.Requests, by a guest).
  defp visitor?(%{"name" => "agent.asked", "by" => %{"kind" => "guest"}}), do: true
  defp visitor?(_item), do: false

  defp visitor(%{"room" => room, "data" => data} = item) do
    title =
      with id when is_integer(id) <- Notebook.Collaboration.page_id(room),
           %Notebook.Pages.Page{title: title} <- Repo.get(Notebook.Pages.Page, id),
           do: title,
           else: (_ -> "a page")

    %{
      "kind" => "visitor",
      "item_id" => item["id"],
      "request" => data["request"],
      "room" => room,
      "text" => data["text"],
      "title" => title
    }
  end

  @doc """
  A visitor asks a bot on a published page (`guest`, its key of
  `Issho.Guests`): the bot's answer comes to `{:bot_answer, request, words}`
  on `"bots:answer:<request>"`, which the caller is subscribed to. Gives the
  request's id, or why not (`:too_many` past a visitor's limit).
  """
  def ask_public(%Notebook.Pages.Page{} = page, %Bot{} = bot, guest, text) do
    room = Notebook.Collaboration.room(page)

    with {:ok, request} <- Issho.Requests.ask(Notebook.Issho, room, guest, text, agent: key(bot)) do
      Phoenix.PubSub.subscribe(Notebook.PubSub, "bots:answer:" <> request.id)
      {:ok, request.id}
    end
  end

  @doc "A page was made: the bots that take new pages and may read it look at it."
  def page_created(%Notebook.Pages.Page{} = page) do
    from(b in Bot, where: b.on_new_page and b.enabled, preload: :user)
    |> Repo.all()
    |> Enum.filter(&Permissions.allowed?(scope(&1), :read, page))
    |> Enum.each(&enqueue(&1, %{"kind" => "new_page", "page_id" => page.id}))

    :ok
  end

  @doc "The bots whose schedule has come: each runs, and its next time is set."
  def due(now \\ DateTime.utc_now(:second)) do
    from(b in Bot, where: b.enabled and not is_nil(b.next_run_at) and b.next_run_at <= ^now)
    |> Repo.all()
    |> Enum.each(fn bot ->
      bot |> Ecto.Changeset.change(next_run_at: next_run(bot.schedule, now)) |> Repo.update!()
      enqueue(bot, %{"kind" => "schedule"})
    end)
  end

  defp next_run(schedule, now \\ DateTime.utc_now(:second))
  defp next_run(nil, _now), do: nil

  defp next_run(schedule, now),
    do: Schedule.next(schedule, now, Notebook.Notifications.time_zone())

  @doc "The schedule's next time, in words: for the bots' page."
  def describe_schedule(%Bot{schedule: nil}), do: nil
  def describe_schedule(%Bot{schedule: schedule}), do: Schedule.describe(schedule)

  @doc false
  def enqueue(%Bot{} = bot, trigger) do
    %{"bot_id" => bot.id, "trigger" => trigger}
    |> Notebook.Bots.Worker.new()
    |> Oban.insert()
  end
end
