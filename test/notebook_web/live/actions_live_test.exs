defmodule NotebookWeb.ActionsLiveTest do
  # What a person does from the page and an agent does as a tool are the
  # same action (Notebook.Actions): the same rules, the room hears each
  # done by whoever did it, and a page off limits to agents refuses only
  # the agent.
  use NotebookWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Jumon.Test
  import Notebook.AccountsFixtures

  alias Notebook.Accounts.Scope
  alias Notebook.Cardbox, as: Box
  alias Notebook.{Databases, Pages, Repo, Spaces}

  setup %{conn: conn} do
    hanzo = user_fixture(%{name: "Hattori Hanzo"})
    yuki = user_fixture(%{name: "Yuki Hattori"})
    scope = Scope.for_user(hanzo)
    {:ok, forge} = Spaces.create_team(scope, %{name: "The forge"})
    {:ok, _} = Spaces.add_member(scope, forge, yuki, "commenter")
    {:ok, page} = Pages.create(scope, %{"title" => "Commissions", "space_id" => forge.id})
    room = Notebook.Collaboration.room(page)
    :ok = Issho.Events.subscribe(Notebook.Issho, room)

    on_exit(fn ->
      for user <- [hanzo, yuki],
          do: Issho.Agents.leave(Notebook.Issho, "agent:#{user.id}", room)
    end)

    %{conn: conn, hanzo: hanzo, yuki: yuki, scope: scope, forge: forge, page: page}
  end

  defp ctx(user) do
    Issho.Tool.Context.new(
      Notebook.Issho,
      %{id: "agent:#{user.id}", name: "Claude Code", kind: :agent},
      on_behalf_of: user
    )
  end

  defp tool(name, args, user), do: Issho.Tools.call(Notebook.Tools.all(), name, args, ctx(user))

  test "a page's title and due date, from the palette and from an agent", %{
    conn: conn,
    hanzo: hanzo,
    page: page
  } do
    hanzo_key = to_string(hanzo.id)
    agent_key = "agent:#{hanzo.id}"
    {:ok, view, _html} = live(log_in_user(conn, hanzo), ~p"/pages/#{page.id}")

    assert %{"ok" => true} = run(view, :rename_page, %{title: "Blades"})

    assert_receive {Issho, :event,
                    %Issho.Event{
                      name: "action.done",
                      by: %{key: ^hanzo_key},
                      data: %{action: "rename_page", title: "Blades"}
                    }}

    assert {:ok, "Renamed: Blades of autumn."} =
             tool("rename_page", %{"page_id" => page.id, "title" => "Blades of autumn"}, hanzo)

    assert_receive {Issho, :event,
                    %Issho.Event{
                      name: "action.done",
                      by: %{key: ^agent_key, on_behalf_of: %{key: ^hanzo_key}},
                      data: %{action: "rename_page"}
                    }}

    assert {:ok, "Blades of autumn is due on 2026-11-02."} =
             tool("set_due_date", %{"page_id" => page.id, "due" => "2026-11-02"}, hanzo)

    assert Repo.get!(Pages.Page, page.id).due_on == ~D[2026-11-02]

    assert {:error, "Give the day as 2026-11-02" <> _} =
             tool("set_due_date", %{"page_id" => page.id, "due" => "soon"}, hanzo)
  end

  test "the same rules for both: a reader may not, and off limits to agents, the agent may not",
       %{conn: conn, scope: scope, hanzo: hanzo, yuki: yuki, page: page} do
    # Yuki comments: the palette offers her no rename, and her agent is refused.
    {:ok, view, _html} = live(log_in_user(conn, yuki), ~p"/pages/#{page.id}")
    refute "Rename this page…" in (view |> actions() |> names())

    assert {:error, "The room's policy does not allow this."} =
             tool("rename_page", %{"page_id" => page.id, "title" => "Mine"}, yuki)

    {:ok, page} = Pages.set_closed_to_agents(scope, page, true)

    assert {:error, _closed} =
             tool("rename_page", %{"page_id" => page.id, "title" => "Agents'"}, hanzo)

    {:ok, view, _html} = live(log_in_user(build_conn(), hanzo), ~p"/pages/#{page.id}")
    assert %{"ok" => true} = run(view, :rename_page, %{title: "Hanzo's"})
    assert Repo.get!(Pages.Page, page.id).title == "Hanzo's"
  end

  test "a database's Record button and an agent's add_records", %{
    conn: conn,
    scope: scope,
    forge: forge,
    hanzo: hanzo
  } do
    {:ok, db} =
      Pages.create(scope, %{"title" => "Orders", "kind" => "database", "space_id" => forge.id})

    collection = Databases.collection(db)
    room = Notebook.Collaboration.room(db)
    :ok = Issho.Events.subscribe(Notebook.Issho, room)
    on_exit(fn -> Issho.Agents.leave(Notebook.Issho, "agent:#{hanzo.id}", room) end)

    {:ok, view, _html} = live(log_in_user(conn, hanzo), ~p"/pages/#{db.id}")
    view |> element("button[phx-click='db_add_record']") |> render_click()

    assert_receive {Issho, :event,
                    %Issho.Event{name: "action.done", data: %{action: "add_records", count: 1}}}

    assert {:ok, %{"records" => [%{"Name" => "A tantō"}]}} =
             tool(
               "add_records",
               %{"page_id" => db.id, "records" => [%{"Name" => "A tantō"}]},
               hanzo
             )

    assert_receive {Issho, :event,
                    %Issho.Event{name: "action.done", data: %{action: "add_records", count: 1}}}

    assert {:ok, records} = Box.list(collection, %{}, limit: 10)
    assert length(records) == 2
  end
end
