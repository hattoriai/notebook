defmodule NotebookWeb.InboxLiveTest do
  # SQLite takes one writer at a time: these write a lot, so they run alone.
  use NotebookWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Notebook.AccountsFixtures

  alias Notebook.Accounts.Scope
  alias Notebook.{Notifications, Spaces}

  setup %{conn: conn} do
    hanzo = user_fixture(%{name: "Hattori Hanzo"})
    yuki = user_fixture(%{name: "Yuki Hattori"})
    {:ok, tea} = Spaces.create_team(Scope.for_user(yuki), %{name: "Tea house"})
    {:ok, _} = Spaces.add_member(Scope.for_user(yuki), tea, hanzo, "editor")

    %{conn: log_in_user(conn, hanzo), hanzo: hanzo, yuki: yuki}
  end

  test "the sidebar's Inbox says how many are unread, and opens the Inbox", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert view |> element("#sidebar-inbox") |> render() =~ "1 unread"

    assert {:ok, _inbox, html} =
             view |> element("#sidebar-inbox") |> render_click() |> follow_redirect(conn)

    assert html =~ "Yuki Hattori added you to Tea house"
  end

  test "the Inbox reads, keeps unread, archives and brings back", %{conn: conn, hanzo: hanzo} do
    {:ok, view, html} = live(conn, ~p"/inbox")
    assert html =~ "Today"
    [%{id: id}] = Chime.feed(Notifications.id(hanzo))

    assert has_element?(view, "#inbox-#{id}.is-unread")
    view |> element("#inbox-#{id} button[phx-click=read]") |> render_click()
    refute has_element?(view, "#inbox-#{id}.is-unread")

    view |> element("#inbox-#{id} button[phx-click=unread]") |> render_click()
    assert has_element?(view, "#inbox-#{id}.is-unread")

    view |> element("#inbox-#{id} button[phx-click=archive]") |> render_click()
    refute has_element?(view, "#inbox-#{id}")
    assert render(view) =~ "Nothing here yet"

    {:ok, archived, _html} = live(conn, ~p"/inbox?show=archived")
    assert has_element?(archived, "#inbox-#{id}")
    archived |> element("#inbox-#{id} button[phx-click=unarchive]") |> render_click()
    refute has_element?(archived, "#inbox-#{id}")
  end

  test "the Inbox follows what comes", %{conn: conn, hanzo: hanzo, yuki: yuki} do
    {:ok, view, _html} = live(conn, ~p"/inbox")
    {:ok, forge} = Spaces.create_team(Scope.for_user(yuki), %{name: "The garden"})
    {:ok, _} = Spaces.add_member(Scope.for_user(yuki), forge, hanzo, "viewer")

    assert render(view) =~ "Yuki Hattori added you to The garden"
  end

  test "the bell beside the avatar shows the latest, and the way to the Inbox", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, ".topbar-bell .chime-dot")
    view |> element(".topbar-bell .chime-bell") |> render_click()
    assert has_element?(view, ".topbar-bell .chime-item", "Yuki Hattori added you to Tea house")
    assert has_element?(view, ".topbar-bell-all[href='/inbox']")
  end
end
