defmodule NotebookWeb.NotebookDatesTest do
  use NotebookWeb.ConnCase
  import Phoenix.LiveViewTest
  import Koyomi.Test
  alias Notebook.{Accounts, Pages}
  alias Notebook.Accounts.Scope

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.register_user(%{
        name: "Nina Writer",
        email: "nina@example.test",
        password: "long enough password"
      })

    %{conn: log_in_user(conn, user), scope: Scope.for_user(user)}
  end

  test "a new page takes its dates from the pickers", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/pages/new")

    for id <- ~w(page_due_on_picker page_covers_picker page_review_at_picker page_revisit_picker) do
      assert has_element?(view, "##{id}[phx-hook='Koyomi']")
    end

    pick(view, "page_due_on_picker", ~D[2027-03-12])

    view
    |> form("#new-page",
      page: %{
        title: "Lisbon trip",
        due_on: "2027-03-12",
        covers: %{from: "2027-03-15", to: "2027-03-19"},
        review_at: "2027-03-10T14:00:00Z",
        revisit: "FREQ=WEEKLY;BYDAY=MO"
      }
    )
    |> render_submit()

    page = Notebook.Repo.get_by!(Notebook.Pages.Page, title: "Lisbon trip")
    assert page.due_on == ~D[2027-03-12]
    assert page.covers == Date.range(~D[2027-03-15], ~D[2027-03-19])

    {:ok, _view, html} = live(conn, ~p"/pages/#{page.id}")
    assert html =~ "Friday, 12 March 2027"
    assert html =~ "15 March – 19 March 2027 · 5 days"
    assert html =~ "Wednesday, 10 March 2027 at 14:00 (Lisbon time)"
    assert html =~ "Weekly on Monday"
  end

  test "a review on a Saturday shows the rule's error", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/pages/new")
    html = pick(view, "page_review_at_picker", ~U[2027-03-13 14:00:00Z])
    assert html =~ "page-date-error"
  end

  test "the review picker offers the free hours", %{conn: conn, scope: scope} do
    {:ok, _taken} =
      Pages.create(scope, %{"title" => "Budget", "review_at" => "2027-03-15T11:00:00Z"})

    {:ok, view, _html} = live(conn, ~p"/pages/new")
    reply = request_days(view, "page_review_at_picker", ~D[2027-03-15], ~D[2027-03-15])
    slots = reply["days"]["2027-03-15"]["slots"]

    assert length(slots) == 7
    assert Enum.any?(slots, &(&1["disabled"] && &1["label"] == "Taken: Budget"))
  end

  test "the index calendar marks the pages' days and filters the list", %{
    conn: conn,
    scope: scope
  } do
    {:ok, _} = Pages.create(scope, %{"title" => "Due one", "due_on" => "2027-03-12"})
    {:ok, _} = Pages.create(scope, %{"title" => "Undated"})

    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#notebook-calendar[phx-hook='Koyomi']")

    reply = request_days(view, "notebook-calendar", ~D[2027-03-01], ~D[2027-03-31])
    assert reply["days"]["2027-03-12"]["title"] == "Due: Due one"
    assert reply["days"]["2027-03-12"]["marks"] == ["accent"]

    html = view |> element("#notebook-calendar") |> render_hook("day", %{"value" => "2027-03-12"})
    assert html =~ "12 March 2027"
    assert has_element?(view, ".page-list .page-row", "Due one")
    refute has_element?(view, ".page-list .page-row", "Undated")

    view |> element("button", "Show every page") |> render_click()
    assert has_element?(view, ".page-list .page-row", "Undated")
  end
end
