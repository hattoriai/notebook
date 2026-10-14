defmodule NotebookWeb.NotebookCommandsTest do
  use NotebookWeb.ConnCase
  import Phoenix.LiveViewTest
  import Jumon.Test
  alias Notebook.{Accounts, Pages, Repo}
  alias Notebook.Accounts.Scope
  alias Notebook.Pages.Page

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.register_user(%{
        name: "Nina Writer",
        email: "nina@example.test",
        password: "long enough password"
      })

    %{conn: log_in_user(conn, user), scope: Scope.for_user(user)}
  end

  test "the palette has the notebook's actions on every page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#jumon[phx-hook='Jumon']")
    assert has_element?(view, "#index-commands")

    names = view |> actions() |> names()
    assert "New page" in names
    assert "All pages" in names
    assert "Log out" in names
    assert "Show a day" in names
  end

  test "a search finds pages by their title and their words", %{conn: conn, scope: scope} do
    {:ok, page} = Pages.create(scope, %{"title" => "Lisbon trip", "due_on" => "2027-03-12"})
    {:ok, _other} = Pages.create(scope, %{"title" => "Budget"})

    {:ok, view, _html} = live(conn, ~p"/")
    results = view |> search("lisbon") |> Enum.filter(&(&1["source"] == "pages"))

    assert [%{"name" => "Lisbon trip", "subtitle" => "Due 12 Mar · Nina Writer"} = result] =
             results

    assert result["id"] == "pages:#{page.id}"
  end

  test "a search forgives a typo in a title", %{conn: conn, scope: scope} do
    {:ok, _page} = Pages.create(scope, %{"title" => "A tour of Notebook"})

    {:ok, view, _html} = live(conn, ~p"/")
    results = view |> search("notebok") |> Enum.filter(&(&1["source"] == "pages"))

    assert ["A tour of Notebook"] = names(results)
  end

  test "a day from the palette filters the list", %{conn: conn, scope: scope} do
    today = Koyomi.Rules.today(Page.review_rules())

    {:ok, _due} =
      Pages.create(scope, %{"title" => "Due today", "due_on" => Date.to_iso8601(today)})

    {:ok, _undated} = Pages.create(scope, %{"title" => "Undated"})

    {:ok, view, _html} = live(conn, ~p"/")
    assert %{"ok" => true} = run(view, "day-#{today}")

    html = render(view)
    assert html =~ "Due today"
    refute html =~ "Undated"

    assert %{"ok" => true} = run(view, :all_days)
    assert render(view) =~ "Undated"
  end

  test "a page renames itself and takes a due date from the palette", %{
    conn: conn,
    scope: scope
  } do
    {:ok, page} = Pages.create(scope, %{"title" => "Draft"})
    {:ok, view, _html} = live(conn, ~p"/pages/#{page.id}")

    assert %{"ok" => true} = run(view, :rename_page, %{title: "Lisbon trip"})
    assert render(view) =~ "Page renamed"
    assert Repo.get!(Page, page.id).title == "Lisbon trip"

    tomorrow = Date.add(Koyomi.Rules.today(Page.review_rules()), 1)
    assert %{"ok" => true} = run(view, :due_page, %{due: Date.to_iso8601(tomorrow)})
    assert Repo.get!(Page, page.id).due_on == tomorrow

    assert %{"ok" => true} = run(view, :due_page, %{due: "none"})
    assert Repo.get!(Page, page.id).due_on == nil
  end

  test "the palette refuses a title or a day that the page cannot take", %{
    conn: conn,
    scope: scope
  } do
    {:ok, page} = Pages.create(scope, %{"title" => "Draft"})
    {:ok, view, _html} = live(conn, ~p"/pages/#{page.id}")

    assert %{"error" => "invalid", "arg" => "title"} =
             run(view, :rename_page, %{title: String.duplicate("a", 161)})

    assert %{"error" => "invalid", "arg" => "due"} = run(view, :due_page, %{due: "2001-01-01"})
    assert Repo.get!(Page, page.id).title == "Draft"
  end
end
