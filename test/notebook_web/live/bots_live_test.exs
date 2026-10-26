defmodule NotebookWeb.BotsLiveTest do
  # SQLite takes one writer at a time: these write a lot, so they run alone.
  use NotebookWeb.ConnCase, async: false
  use Oban.Testing, repo: Notebook.Repo, engine: Oban.Engines.Lite

  import Phoenix.LiveViewTest
  import Notebook.AccountsFixtures

  alias Notebook.Accounts.Scope
  alias Notebook.{Bots, Pages, Publishing, Repo, Spaces}

  setup %{conn: conn} do
    hanzo =
      user_fixture(%{name: "Hattori Hanzo"})
      |> Ecto.Changeset.change(admin: true)
      |> Repo.update!()

    yuki = user_fixture(%{name: "Yuki Hattori"})
    admin = Scope.for_user(hanzo)
    {:ok, forge} = Spaces.create_team(admin, %{name: "The forge"})
    on_exit(fn -> Notebook.Secrets.delete("anthropic.api_key") end)
    %{conn: conn, hanzo: hanzo, yuki: yuki, admin: admin, forge: forge}
  end

  test "an admin keeps the key, makes a bot and gives it a role in a space", %{
    conn: conn,
    hanzo: hanzo,
    forge: forge
  } do
    {:ok, view, html} = live(log_in_user(conn, hanzo), ~p"/bots")
    assert html =~ "The notebook comes with none"
    refute Bots.api_key?()

    view |> form("#api-key-form", %{key: "sk-ant-secret"}) |> render_submit()
    assert Bots.api_key?()
    refute render(view) =~ "sk-ant-secret"

    view |> element("button", "New bot") |> render_click()

    view
    |> form("#bot-form",
      bot: %{
        name: "Gardener",
        instructions: "Tidy the tags of new pages.",
        model: "claude-sonnet-5-5",
        tools: ["", "comment", "hand_off"],
        on_new_page: "true",
        budget: "12.50"
      }
    )
    |> render_submit()

    assert [bot] = Bots.list(Scope.for_user(hanzo))

    assert %{
             name: "Gardener",
             model: "claude-sonnet-5-5",
             tools: ["comment", "hand_off"],
             on_new_page: true,
             monthly_budget_cents: 1250
           } = bot

    view
    |> form("#bot-space-#{forge.id}", %{space: forge.id, role: "commenter"})
    |> render_change()

    assert {_, "commenter"} =
             Enum.find(Bots.spaces(bot), fn {space, _} -> space.id == forge.id end)

    assert render(view) =~ "Gardener"
  end

  test "someone who is not an admin is sent away", %{conn: conn, yuki: yuki} do
    assert {:error, {:live_redirect, %{to: "/"}}} = live(log_in_user(conn, yuki), ~p"/bots")
  end

  test "a visitor asks a published page's bot, and reads its answer", %{
    conn: conn,
    admin: admin,
    forge: forge
  } do
    {:ok, page} =
      Pages.create(admin, %{
        "title" => "On folding",
        "space_id" => forge.id,
        "body" => Kotoba.Content.from_markdown("Twelve folds.")
      })

    {:ok, page} = Publishing.publish(admin, page)
    on_exit(fn -> Application.delete_env(:notebook, :publishing) end)
    {:ok, bot} = Bots.create(admin, %{"name" => "Docs", "public" => true, "on_mention" => false})
    {:ok, _} = Bots.set_role(admin, bot, forge, "viewer")
    :ok = Bots.put_api_key(admin, "sk-ant-test")

    {:ok, view, html} = live(conn, Publishing.path(page))
    assert html =~ "Ask Docs"

    view
    |> form("#ask-form-#{bot.id}", %{bot: bot.id, question: "How many folds?"})
    |> render_submit()

    assert render(view) =~ "Docs is thinking"

    job = eventually(fn -> List.first(all_enqueued(worker: Notebook.Bots.Worker)) end)

    Req.Test.stub(Bots.Claude, fn conn ->
      Req.Test.json(conn, %{
        "content" => [%{"type" => "text", "text" => "Twelve, said the page."}],
        "stop_reason" => "end_turn",
        "usage" => %{"input_tokens" => 10, "output_tokens" => 5}
      })
    end)

    :ok = perform_job(Notebook.Bots.Worker, job.args)
    assert eventually(fn -> render(view) =~ "Twelve, said the page." end)
  end

  defp eventually(fun, tries \\ 100) do
    case fun.() do
      falsy when falsy in [nil, false] and tries > 0 ->
        Process.sleep(10)
        eventually(fun, tries - 1)

      result ->
        result
    end
  end
end
