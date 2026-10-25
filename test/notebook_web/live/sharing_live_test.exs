defmodule NotebookWeb.SharingLiveTest do
  # SQLite takes one writer at a time: these write a lot, so they run alone.
  use NotebookWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Notebook.AccountsFixtures

  alias Notebook.Accounts.Scope
  alias Notebook.{Pages, Sharing, Spaces}

  setup %{conn: conn} do
    hanzo = user_fixture(%{name: "Hattori Hanzo"})
    yuki = user_fixture(%{name: "Yuki Hattori"})
    scope = Scope.for_user(hanzo)
    {:ok, forge} = Spaces.create_team(scope, %{name: "The forge"})
    {:ok, plans} = Spaces.create_folder(scope, forge, %{name: "Plans"})

    {:ok, blade} =
      Pages.create(scope, %{
        "title" => "The last blade",
        "space_id" => forge.id,
        "folder_id" => plans.id
      })

    %{
      conn: conn,
      hanzo: hanzo,
      yuki: yuki,
      scope: scope,
      forge: forge,
      plans: plans,
      blade: blade
    }
  end

  test "an editor shares a page with a person and a link, from the Share dialog", %{
    conn: conn,
    hanzo: hanzo,
    yuki: yuki,
    blade: blade
  } do
    {:ok, view, _html} = live(log_in_user(conn, hanzo), ~p"/pages/#{blade.id}")
    view |> element("#share-open") |> render_click()
    assert has_element?(view, ".share-dialog", "Share The last blade")

    view |> form(".share-invite", %{user_id: yuki.id, role: "commenter"}) |> render_submit()
    assert has_element?(view, "#share-#{yuki.id}")

    view |> form(".share-link", %{role: "viewer"}) |> render_change()

    url =
      view
      |> element(".share-url input")
      |> render()
      |> then(&Regex.run(~r/value="([^"]+)"/, &1))
      |> List.last()

    assert url =~ "/pages/#{blade.id}?key="

    view |> element("#share-#{yuki.id} .share-remove") |> render_click()
    refute has_element?(view, "#share-#{yuki.id}")
  end

  test "a person it is shared with finds it under Shared with you, and opens it", %{
    conn: conn,
    scope: scope,
    yuki: yuki,
    blade: blade
  } do
    {:ok, _} = Sharing.share(scope, blade, yuki, "viewer")
    {:ok, view, _html} = live(log_in_user(conn, yuki), ~p"/")
    assert has_element?(view, ".sidebar-shared", "The last blade")

    {:ok, page, html} = live(log_in_user(build_conn(), yuki), ~p"/pages/#{blade.id}")
    assert html =~ "Shared with you"
    refute has_element?(page, "#share-open")
  end

  test "a link opens a page to whoever follows it, signed in", %{
    conn: conn,
    scope: scope,
    yuki: yuki,
    blade: blade
  } do
    conn = log_in_user(conn, yuki)
    assert_raise Sekisho.Denied, fn -> live(conn, ~p"/pages/#{blade.id}") end

    {:ok, token} = Sharing.link(scope, blade, "viewer")
    conn = get(conn, ~p"/pages/#{blade.id}?key=#{token}")
    assert html_response(conn, 200) =~ "The last blade"

    {:ok, _view, html} = live(recycle(conn), ~p"/pages/#{blade.id}")
    assert html =~ "The last blade"
  end

  test "a folder shared opens to its person, with its pages", %{
    conn: conn,
    scope: scope,
    yuki: yuki,
    forge: forge,
    plans: plans
  } do
    {:ok, _} = Sharing.share(scope, plans, yuki, "viewer")

    {:ok, _view, html} =
      live(log_in_user(conn, yuki), ~p"/spaces/#{forge.id}/folders/#{plans.id}")

    assert html =~ "Plans"
    assert html =~ "The last blade"
    assert html =~ "Shared with you"
  end
end
