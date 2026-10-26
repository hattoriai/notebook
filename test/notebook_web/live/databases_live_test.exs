defmodule NotebookWeb.DatabasesLiveTest do
  # SQLite takes one writer at a time: these write a lot, so they run alone.
  use NotebookWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Notebook.AccountsFixtures

  alias Notebook.Accounts.Scope
  alias Notebook.Cardbox, as: Box
  alias Notebook.{Databases, Pages, Spaces}

  setup %{conn: conn} do
    hanzo = user_fixture(%{name: "Hattori Hanzo"})
    yuki = user_fixture(%{name: "Yuki Hattori"})
    scope = Scope.for_user(hanzo)
    {:ok, forge} = Spaces.create_team(scope, %{name: "The forge"})
    {:ok, _} = Spaces.add_member(scope, forge, yuki, "commenter")

    {:ok, page} =
      Pages.create(scope, %{
        "title" => "Commissions",
        "kind" => "database",
        "space_id" => forge.id
      })

    collection = Databases.collection(page)

    {:ok, _} =
      Box.insert(
        collection,
        %{"Name" => "The rain blade", "Status" => "In progress", "Due" => "2026-10-30"},
        actor: scope
      )

    %{conn: conn, hanzo: hanzo, yuki: yuki, scope: scope, page: page, collection: collection}
  end

  defp view_id(collection, type),
    do: Enum.find(Databases.views(collection), &(&1.type == type)).id

  test "a database page shows its views, and switches between them", %{
    conn: conn,
    hanzo: hanzo,
    page: page,
    collection: collection
  } do
    {:ok, view, html} = live(log_in_user(conn, hanzo), ~p"/pages/#{page.id}")
    assert html =~ "Commissions"

    for name <- ~w(Table Board Calendar Chart),
        do: assert(has_element?(view, ".database-view-tab", name))

    assert has_element?(view, ".database-view-tab.is-current", "Table")

    html = view |> element("#view-#{view_id(collection, "board")}") |> render_click()
    assert html =~ "The rain blade"
    assert has_element?(view, ".cardbox-card", "30 Oct 2026")

    view |> element("#view-#{view_id(collection, "calendar")}") |> render_click()
    assert render_hook(view, "db_day", %{"value" => "2026-10-30"}) =~ "The rain blade"
  end

  test "its editors add fields and views, as everyone watching sees", %{
    conn: conn,
    hanzo: hanzo,
    yuki: yuki,
    page: page
  } do
    {:ok, view, _html} = live(log_in_user(conn, hanzo), ~p"/pages/#{page.id}")
    {:ok, other, _html} = live(log_in_user(build_conn(), yuki), ~p"/pages/#{page.id}")

    view |> element("button", "Field") |> render_click()

    view
    |> form("#field-form", field: %{name: "Price", type: "number"})
    |> render_submit()

    assert render(other) =~ "Price"

    view |> element(".database-menu-panel button", "Board") |> render_click()
    assert view |> element(".database-view-tab.is-current") |> render() =~ "Board"
  end

  test "a commenter reads the database and changes nothing", %{yuki: yuki, conn: conn, page: page} do
    {:ok, view, html} = live(log_in_user(conn, yuki), ~p"/pages/#{page.id}")
    assert html =~ "The rain blade"
    refute has_element?(view, ".database-actions")
  end

  test "a money field has its currency, and a repeat its date and status", %{
    conn: conn,
    hanzo: hanzo,
    collection: collection
  } do
    {:ok, view, _html} = live(log_in_user(conn, hanzo), ~p"/pages/#{collection.owner_id}")

    view |> element("button", "Field") |> render_click()
    refute has_element?(view, "#field-form select[name='field[format]']")

    view |> form("#field-form", field: %{name: "Amount", type: "number"}) |> render_change()
    assert has_element?(view, "#field-form select[name='field[format]']")
    refute has_element?(view, "#field-form input[name='field[currency]']")

    view
    |> form("#field-form", field: %{name: "Amount", type: "number", format: "currency"})
    |> render_change()

    view
    |> form("#field-form",
      field: %{name: "Amount", type: "number", format: "currency", currency: "JPY"}
    )
    |> render_submit()

    collection = Box.get_collection!(collection.id)
    assert %{options: %{"currency" => "JPY"}} = Cardbox.Collection.field(collection, "Amount")

    view |> element("button", "Field") |> render_click()
    view |> form("#field-form", field: %{name: "Repeats", type: "repeat"}) |> render_change()
    assert has_element?(view, "#field-form select[name='field[date]'] option", "Moves Due")

    assert has_element?(
             view,
             "#field-form select[name='field[done]'] option",
             "When Status is done"
           )

    view
    |> form("#field-form", field: %{name: "Repeats", type: "repeat", date: "due", done: "status"})
    |> render_submit()

    assert %{options: %{"date" => "due"}} =
             Cardbox.Collection.field(Box.get_collection!(collection.id), "Repeats")
  end

  test "its editors attach files to a record", %{
    conn: conn,
    hanzo: hanzo,
    scope: scope,
    page: page,
    collection: collection
  } do
    {:ok, view, _html} = live(log_in_user(conn, hanzo), ~p"/pages/#{page.id}")
    refute has_element?(view, "button", "Attach")

    {:ok, collection} =
      Databases.add_field(scope, collection, %{"name" => "Invoice", "type" => "file"})

    {:ok, view, _html} = live(log_in_user(conn, hanzo), ~p"/pages/#{page.id}")
    [record] = elem(Box.list(collection), 1)

    view |> element("button", "Attach") |> render_click()
    assert has_element?(view, "#attach-form option", "The rain blade")

    pdf = "%PDF-1.7\n1 0 obj << /Type /Catalog >> endobj\ntrailer << /Root 1 0 R >>\n%%EOF\n"

    upload =
      file_input(view, "#attach-form", :record_files, [
        %{name: "invoice.pdf", content: pdf, type: "application/pdf"}
      ])

    render_upload(upload, "invoice.pdf")

    view
    |> form("#attach-form", attach: %{record: record.id, field: "invoice"})
    |> render_submit()

    assert [%{"name" => "invoice.pdf", "content_type" => "application/pdf", "key" => key}] =
             Box.get(collection, record.id).data["invoice"]

    on_exit(fn -> Storehouse.Local.delete(key) end)

    refute has_element?(view, "#attach-form")
    assert render(view) =~ "Attached."
  end
end
