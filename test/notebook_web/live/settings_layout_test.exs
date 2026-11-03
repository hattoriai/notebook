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
          {~p"/notebook/settings/files", "files", "#storage", "#connecting"},
          {~p"/notebook/settings/publishing", "publishing", "#publishing-form", "#storage"}
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

  test "an admin keeps where published pages are read", %{conn: conn, admin: admin} do
    {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/notebook/settings/publishing")

    view
    |> form("#publishing-form",
      publishing: %{url: "https://hattori.ai", prefix: "", name: "Hattori"}
    )
    |> render_change()

    assert has_element?(view, "#publishing-example", "https://hattori.ai/open-source/kotoba")

    view
    |> form("#publishing-form",
      publishing: %{url: "https://hattori.ai", prefix: "", name: "Hattori"}
    )
    |> render_submit()

    assert Notebook.Publishing.config().url == "https://hattori.ai"
    assert Notebook.Publishing.config().name == "Hattori"
  end

  test "password managers stay on the fields of signing in, and off the others", %{
    conn: conn,
    yuki: yuki
  } do
    {:ok, view, _html} = live(log_in_user(conn, yuki), ~p"/account/settings/profile")
    assert has_element?(view, "#name_form input[name='user[name]'][data-1p-ignore]")

    {:ok, view, _html} = live(log_in_user(conn, yuki), ~p"/account/settings/password")
    refute has_element?(view, "#password_form input[type=password][data-1p-ignore]")

    {:ok, view, _html} = live(build_conn(), ~p"/users/log-in")
    refute has_element?(view, "input[type=email][data-1p-ignore]")
  end

  test "an admin gives the site its icon, and takes it away", %{conn: conn, admin: admin} do
    png =
      Base.decode64!(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
      )

    {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/notebook/settings/publishing")
    refute has_element?(view, "#site-icon img")

    view
    |> file_input("#site-icon-form", :site_icon, [
      %{name: "icon.png", content: png, type: "image/png"}
    ])
    |> render_upload("icon.png")

    assert has_element?(view, "#site-icon img[src^='/uploads/kotoba/']")
    assert Notebook.Publishing.config().icon =~ "/uploads/kotoba/"

    view |> element("#site-icon button", "Remove") |> render_click()
    refute has_element?(view, "#site-icon img")
  end
end
