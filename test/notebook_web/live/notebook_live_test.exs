defmodule NotebookWeb.NotebookLiveTest do
  use NotebookWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Notebook.{Accounts, Pages}
  alias Notebook.Accounts.Scope

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.register_user(%{
        name: "Nina Writer",
        email: "nina@example.test",
        password: "long enough password"
      })

    content = Kotoba.Content.from_markdown("## Notes\n\nA useful sentence.")
    {:ok, page} = Pages.create(Scope.for_user(user), %{title: "Release notes", body: content})
    %{conn: log_in_user(conn, user), user: user, page: page}
  end

  test "a new page has Kotoba's default selection menu", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/pages/new")
    assert has_element?(view, "#new-body[data-selection-menu='true']")
  end

  test "the edit page brings its own selection menu, with the callout", %{
    conn: conn,
    page: page
  } do
    {:ok, view, _html} = live(conn, ~p"/pages/#{page.id}/edit")
    menu = "#body-editor #body-selection-menu[data-kotoba-selection-menu]"
    assert has_element?(view, menu)
    assert has_element?(view, "#{menu} button[data-kotoba-command='bold']")
    assert has_element?(view, "#{menu} button[data-kotoba-command='callout:toggle']")
  end

  test "the reader shows who wrote the page and when it changed", %{conn: conn, page: page} do
    {:ok, _view, html} = live(conn, ~p"/pages/#{page.id}")
    assert html =~ "By Nina Writer"
    assert html =~ "Updated #{Calendar.strftime(page.updated_at, "%-d %B %Y")}"
    refute html =~ "Invite someone"
  end

  test "each writer gets a collaboration color of their own", %{user: user} do
    {:ok, other} =
      Accounts.register_user(%{
        name: "Omar Writer",
        email: "omar@example.test",
        password: "long enough password"
      })

    {:ok, page} = Pages.create(Scope.for_user(user), %{title: "Shared"})

    colors =
      for account <- [user, other] do
        {:ok, view, _html} =
          live(log_in_user(build_conn(), account), ~p"/pages/#{page.id}/edit")

        view
        |> element("#body-editor")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.attribute("data-collab")
        |> hd()
        |> JSON.decode!()
        |> get_in(["user", "color"])
      end

    assert length(Enum.uniq(colors)) == 2
  end

  test "a new page has the signed-in writer as its author", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/pages/new")

    # A forged author_id is not cast: the author comes from the scope.
    render_submit(view, "create", %{"page" => %{"title" => "Field notes", "author_id" => "999"}})

    page = Notebook.Repo.get_by!(Notebook.Pages.Page, title: "Field notes")
    assert page.author_id == user.id

    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Nina Writer"
  end

  test "the reader copies Markdown and plain text, with a toast", %{conn: conn, page: page} do
    {:ok, view, _html} = live(conn, ~p"/pages/#{page.id}")

    copy = fn id ->
      view
      |> element(id)
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.attribute("data-copy")
      |> hd()
    end

    assert copy.("#copy-markdown") =~ "## Notes"
    assert copy.("#copy-text") == "Notes\nA useful sentence."
    assert has_element?(view, "#copy-markdown[phx-hook]")

    render_hook(view, "copied", %{"format" => "markdown"})
    assert render(view) =~ "Markdown copied to your clipboard"

    render_hook(view, "copy_failed", %{"format" => "text"})
    assert render(view) =~ "Could not copy the plain text"
  end
end
