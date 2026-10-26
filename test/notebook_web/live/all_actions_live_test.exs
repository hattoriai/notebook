defmodule NotebookWeb.AllActionsLiveTest do
  # Every way a person changes the Notebook is an action an agent can run
  # too (or, for what agents may reach, one only a person runs): the room
  # hears each done, by whoever did it.
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

    {:ok, db} =
      Pages.create(scope, %{"title" => "Orders", "kind" => "database", "space_id" => forge.id})

    collection = Databases.collection(db)
    {:ok, record} = Box.insert(collection, %{"Name" => "The rain blade"}, actor: scope)
    :ok = Issho.Events.subscribe(Notebook.Issho, "page:#{db.id}")

    %{
      conn: log_in_user(conn, hanzo),
      hanzo: hanzo,
      yuki: yuki,
      scope: scope,
      forge: forge,
      db: db,
      collection: collection,
      record: record
    }
  end

  defp ctx(user) do
    Issho.Tool.Context.new(
      Notebook.Issho,
      %{id: "agent:#{user.id}", name: "Claude Code", kind: :agent},
      on_behalf_of: user
    )
  end

  defp tool(name, args, user), do: Issho.Tools.call(Notebook.Tools.all(), name, args, ctx(user))

  defp done(action) do
    assert_receive {Issho, :event,
                    %Issho.Event{name: "action.done", data: %{action: ^action}} = event}

    event
  end

  defp grid(collection), do: "cardbox-#{collection.id}"

  test "a table's cells, rows and deletes are the record actions, as the person", %{
    conn: conn,
    hanzo: hanzo,
    db: db,
    collection: collection,
    record: record
  } do
    hanzo_key = to_string(hanzo.id)
    {:ok, view, _html} = live(conn, ~p"/pages/#{db.id}")

    assert :ok = Masu.Test.edit(view, grid(collection), [{record.id, "name", "The autumn blade"}])
    assert %{by: %{key: ^hanzo_key}} = done("update_records")
    assert Box.get(collection, record.id).data["name"] == "The autumn blade"

    assert {:ok, [id]} = Masu.Test.add_rows(view, grid(collection), [%{"name" => "A tantō"}])
    assert %{by: %{key: ^hanzo_key}} = done("add_records")

    assert {:ok, _undo} = Masu.Test.delete_rows(view, grid(collection), [id])
    assert %{by: %{key: ^hanzo_key}} = done("delete_records")
    assert Box.get(collection, id) == nil

    # A cell changed since the person saw it is refused, as before.
    assert {:error, [{_id, "name", _message}]} =
             Masu.Test.edit(view, grid(collection), [
               {record.id, "name", "Mine", "The rain blade"}
             ])

    # The agent's are the same actions.
    assert {:ok, %{"deleted" => [_]}} =
             tool("delete_records", %{"page_id" => db.id, "ids" => [record.id]}, hanzo)

    assert %{by: %{kind: :agent}} = done("delete_records")
  end

  test "a card moved on the board is the record actions, as the person", %{
    conn: conn,
    db: db,
    collection: collection,
    record: record
  } do
    board = Enum.find(Databases.views(collection), &(&1.type == "board"))
    {:ok, view, _html} = live(conn, ~p"/pages/#{db.id}")
    view |> element(".database-view-tab", "Board") |> render_click()

    render_hook(view, "db_move", %{
      "v" => 1,
      "ids" => [to_string(record.id)],
      "parent" => "Done",
      "index" => 0
    })

    assert board.id
    done("move_record")
    assert Box.get(collection, record.id).data["status"] == "done"
  end

  test "a page made, moved, archived and restored, by the person and by the agent", %{
    conn: conn,
    hanzo: hanzo,
    forge: forge
  } do
    :ok = Issho.Events.subscribe(Notebook.Issho, "space:#{forge.id}")
    {:ok, view, _html} = live(conn, ~p"/pages/new")

    render_submit(view, "create", %{
      "page" => %{"title" => "Field notes", "place" => "#{forge.id}:"}
    })

    assert %{room: room} = done("create_page")
    assert room == "space:#{forge.id}"
    page = Repo.get_by!(Pages.Page, title: "Field notes")

    :ok = Issho.Events.subscribe(Notebook.Issho, "page:#{page.id}")
    {:ok, view, _html} = live(conn, ~p"/pages/#{page.id}")
    assert %{"ok" => true} = run(view, :archive_page)
    done("archive_page")
    assert Repo.get!(Pages.Page, page.id).archived_at

    assert {:ok, "Restored Field notes."} = tool("restore_page", %{"page_id" => page.id}, hanzo)
    assert %{by: %{kind: :agent}} = done("restore_page")
    refute Repo.get!(Pages.Page, page.id).archived_at

    private = Spaces.private!(hanzo)

    assert {:ok, "Moved Field notes to Private."} =
             tool("move_page", %{"page_id" => page.id, "space_id" => private.id}, hanzo)

    assert Repo.get!(Pages.Page, page.id).space_id == private.id
  end

  test "a database's fields and views, by the person and by the agent", %{
    conn: conn,
    hanzo: hanzo,
    db: db
  } do
    {:ok, view, _html} = live(conn, ~p"/pages/#{db.id}")
    view |> element("button", "Field") |> render_click()
    view |> form("#field-form", field: %{name: "Price", type: "number"}) |> render_submit()
    done("add_field")

    view |> element(".database-menu-panel button", "Calendar") |> render_click()
    done("add_view")

    assert {:ok, %{"fields" => fields}} =
             tool(
               "add_field",
               %{"page_id" => db.id, "name" => "Smith", "type" => "person"},
               hanzo
             )

    assert Enum.any?(fields, &(&1["name"] == "Smith"))
  end

  test "sharing and agents' access are a person's actions only", %{
    conn: conn,
    hanzo: hanzo,
    yuki: yuki,
    db: db
  } do
    {:ok, view, _html} = live(conn, ~p"/pages/#{db.id}")
    view |> element("#share-open") |> render_click()

    view
    |> form("#share-dialog-invite", user_id: to_string(yuki.id), role: "editor")
    |> render_submit()

    assert %{data: %{role: "editor"}} = done("share")

    # No agent is given them, nor may run them.
    refute "share" in Enum.map(Notebook.Tools.all(), & &1.name())

    assert {:error, "Only a person does this" <> _} =
             Issho.Action.invoke(
               Notebook.Issho,
               Notebook.Actions.SetAgents,
               %{page_id: db.id, closed: false},
               %{id: "agent:#{hanzo.id}", name: "Claude Code", kind: :agent},
               on_behalf_of: hanzo
             )
             |> then(fn {:error, reason} -> {:error, Issho.Action.message(reason)} end)
  end

  test "an agent finds what it may do on a page, and why not", %{hanzo: hanzo, yuki: yuki, db: db} do
    assert {:ok, %{"actions" => actions}} =
             tool("list_actions", %{"room" => "page:#{db.id}"}, hanzo)

    assert Enum.all?(actions, & &1.allowed)
    assert "update_records" in Enum.map(actions, & &1.name)

    # Yuki comments: her agent may change nothing here, and is told why.
    assert {:ok, %{"actions" => actions}} =
             tool("list_actions", %{"room" => "page:#{db.id}"}, yuki)

    assert Enum.all?(actions, &(not &1.allowed))
  end
end
