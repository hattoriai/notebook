defmodule NotebookWeb.PageIconLiveTest do
  use NotebookWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Notebook.AccountsFixtures

  alias Notebook.Accounts.Scope
  alias Notebook.{Pages, Publishing, Spaces}

  setup %{conn: conn} do
    hanzo = user_fixture(%{name: "Hattori Hanzo"})
    grace = user_fixture(%{name: "Grace"})
    scope = Scope.for_user(hanzo)
    {:ok, forge} = Spaces.create_team(scope, %{name: "The forge"})
    {:ok, _} = Spaces.add_member(scope, forge, grace, "viewer")
    {:ok, blade} = Pages.create(scope, %{"title" => "Kotoba", "space_id" => forge.id})
    on_exit(fn -> Application.delete_env(:notebook, :publishing) end)
    %{conn: conn, hanzo: hanzo, grace: grace, scope: scope, forge: forge, blade: blade}
  end

  test "its editor chooses its icon: before its title and in the sidebar, and its usual one again",
       %{conn: conn, hanzo: hanzo, blade: blade} do
    {:ok, view, _html} = live(log_in_user(conn, hanzo), ~p"/pages/#{blade}")
    assert has_element?(view, "#page-icon-form .erabi")
    refute has_element?(view, "#page-title .page-title-icon")

    view |> form("#page-icon-form") |> render_change(%{"icon" => "⚔️"})
    assert has_element?(view, "#page-title .notebook-icon-emoji", "⚔️")
    assert has_element?(view, ".sidebar-page.is-current .notebook-icon-emoji", "⚔️")

    view |> element("#page-icon-reset") |> render_click()
    refute has_element?(view, "#page-title .page-title-icon")
  end

  test "its readers see its icon, and do not change it", %{
    conn: conn,
    grace: grace,
    scope: scope,
    blade: blade
  } do
    {:ok, blade} = Pages.set_icon(scope, blade, "hero-book-open")
    {:ok, view, _html} = live(log_in_user(conn, grace), ~p"/pages/#{blade}")

    assert has_element?(view, "#page-title .page-title-icon")
    refute has_element?(view, "#page-icon")
  end

  test "a published page shows its icon before its title, and in the browser's tab",
       %{conn: conn, scope: scope, blade: blade} do
    {:ok, blade} = Pages.set_icon(scope, blade, "🔥")
    {:ok, blade} = Publishing.publish(scope, blade)
    blade = Notebook.Repo.preload(blade, [:space, :folder], force: true)
    path = URI.parse(Publishing.url(blade)).path

    {:ok, view, _html} = live(conn, path)
    assert has_element?(view, "#public-title .notebook-icon-emoji", "🔥")

    html = conn |> get(path) |> html_response(200)
    assert html =~ ~s(rel="icon" href="data:image/svg+xml,)
  end
end
