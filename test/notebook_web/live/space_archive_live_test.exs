defmodule NotebookWeb.SpaceArchiveLiveTest do
  use NotebookWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Notebook.AccountsFixtures

  alias Notebook.Accounts.Scope
  alias Notebook.Spaces

  setup %{conn: conn} do
    hanzo = user_fixture(%{name: "Hattori Hanzo"})
    yuki = user_fixture(%{name: "Yuki Hattori"})
    {:ok, forge} = Spaces.create_team(Scope.for_user(hanzo), %{name: "The forge"})
    {:ok, _} = Spaces.add_member(Scope.for_user(hanzo), forge, yuki, "editor")
    %{conn: log_in_user(conn, hanzo), hanzo: hanzo, yuki: yuki, forge: forge}
  end

  test "its admin chooses its icon, and the sidebar shows it", %{conn: conn, forge: forge} do
    {:ok, view, _html} = live(conn, ~p"/spaces/#{forge.id}")
    assert has_element?(view, "#space-icon-picker")

    view |> form("#space-icon-form") |> render_change(%{"icon" => "⚔️"})
    assert has_element?(view, ".sidebar-space .notebook-icon-emoji", "⚔️")
    assert has_element?(view, "#space-icon-reset")

    view |> element("#space-icon-reset") |> render_click()
    refute has_element?(view, ".notebook-icon-emoji", "⚔️")
  end

  test "an editor neither chooses its icon nor archives it", %{
    conn: conn,
    yuki: yuki,
    forge: forge
  } do
    {:ok, view, _html} = live(log_in_user(conn, yuki), ~p"/spaces/#{forge.id}")
    refute has_element?(view, "#space-icon")
    refute has_element?(view, "#space-archive")
  end

  test "archived from its page, then restored, then deleted for good", %{
    conn: conn,
    hanzo: hanzo,
    forge: forge
  } do
    {:ok, view, _html} = live(conn, ~p"/spaces/#{forge.id}")

    assert {:error, {:live_redirect, %{to: "/archive"}}} =
             view |> element("#space-archive") |> render_click()

    {:ok, view, _html} = live(conn, ~p"/archive")
    assert has_element?(view, "#archived-space-#{forge.id}", "The forge")
    refute has_element?(view, ".sidebar-space", "The forge")

    view |> element("#archived-space-#{forge.id} button", "Restore") |> render_click()
    refute has_element?(view, "#archived-space-#{forge.id}")
    assert has_element?(view, ".sidebar-space", "The forge")

    {:ok, _} = Spaces.archive(Scope.for_user(hanzo), forge)

    {:ok, view, _html} = live(conn, ~p"/archive")
    view |> element("#archived-space-#{forge.id} button", "Delete forever") |> render_click()
    refute has_element?(view, "#archived-space-#{forge.id}")
    refute Notebook.Repo.get(Notebook.Spaces.Space, forge.id)
  end
end
