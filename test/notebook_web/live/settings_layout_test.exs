defmodule NotebookWeb.SettingsLayoutTest do
  use NotebookWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Notebook.AccountsFixtures

  setup do
    %{
      admin: user_fixture(%{name: "Hattori Hanzo", admin: true}),
      yuki: user_fixture(%{name: "Yuki Hattori"})
    }
  end

  test "the notebook's settings: a group at each address, named in the nav", %{
    conn: conn,
    admin: admin
  } do
    conn = log_in_user(conn, admin)

    for {path, current, shown, hidden} <- [
          {~p"/notebook/settings", "people", "#joining", "#storage"},
          {~p"/notebook/settings/people", "people", "#joining", "#connecting"},
          {~p"/notebook/settings/agents", "agents", "#connecting", "#joining"},
          {~p"/notebook/settings/bots", "bots", "#bots-list", "#joining"},
          {~p"/notebook/settings/files", "files", "#storage", "#connecting"}
        ] do
      {:ok, view, _html} = live(conn, path)
      assert has_element?(view, "#settings-nav-#{current}[aria-current=page]")
      assert has_element?(view, shown)
      refute has_element?(view, hidden)
    end
  end

  test "the account's settings: a group at each address", %{conn: conn, yuki: yuki} do
    conn = log_in_user(conn, yuki)

    for {path, current, shown, hidden} <- [
          {~p"/account/settings", "profile", "#name_form", "#password_form"},
          {~p"/account/settings/profile", "profile", "#handle_form", "#password_form"},
          {~p"/account/settings/password", "password", "#password_form", "#name_form"},
          {~p"/account/settings/notifications", "notifications", "#notifications-prefs",
           "#name_form"}
        ] do
      {:ok, view, _html} = live(conn, path)
      assert has_element?(view, "#settings-nav-#{current}[aria-current=page]")
      assert has_element?(view, shown)
      refute has_element?(view, hidden)
    end

    # The notifications are Erabi's pickers: no browser <select> but theirs.
    {:ok, view, _html} = live(conn, ~p"/account/settings/notifications")
    assert has_element?(view, "#notifications .erabi")
    refute has_element?(view, "select:not(.erabi-native)")

    # The account's nav has no notebook settings.
    {:ok, view, _html} = live(conn, ~p"/account/settings")
    refute has_element?(view, "#settings-nav-files")
  end

  test "the old addresses are gone", %{conn: conn, admin: admin} do
    conn = log_in_user(conn, admin)

    for path <- ["/admin", "/bots", "/users/settings"] do
      assert_error_sent 404, fn -> get(conn, path) end
    end
  end
end
