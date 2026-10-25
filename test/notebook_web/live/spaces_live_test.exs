defmodule NotebookWeb.SpacesLiveTest do
  # SQLite takes one writer at a time: these write a lot, so they run alone.
  use NotebookWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Jumon.Test
  import Notebook.AccountsFixtures

  alias Notebook.Accounts.Scope
  alias Notebook.{Pages, Spaces}

  setup %{conn: conn} do
    hanzo = user_fixture(%{name: "Hattori Hanzo"})
    yuki = user_fixture(%{name: "Yuki Hattori"})
    scope = Scope.for_user(hanzo)
    {:ok, forge} = Spaces.create_team(scope, %{name: "The forge", description: "Blades."})
    {:ok, _} = Spaces.add_member(scope, forge, yuki, "commenter")
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

  test "the sidebar has the person's spaces, folders and pages", %{
    conn: conn,
    hanzo: hanzo,
    yuki: yuki
  } do
    {:ok, letter} =
      Pages.create(Scope.for_user(hanzo), %{
        "title" => "A letter",
        "space_id" => Spaces.private!(hanzo).id
      })

    {:ok, view, _html} = live(log_in_user(conn, hanzo), ~p"/")
    assert has_element?(view, "#sidebar .sidebar-space-name", "The forge")
    assert has_element?(view, "#sidebar .sidebar-folder-link", "Plans")
    assert has_element?(view, "#sidebar .sidebar-page", "The last blade")
    assert has_element?(view, "#sidebar .sidebar-page", letter.title)

    {:ok, view, _html} = live(log_in_user(build_conn(), yuki), ~p"/")
    assert has_element?(view, "#sidebar .sidebar-page", "The last blade")
    refute has_element?(view, "#sidebar .sidebar-page", letter.title)
  end

  test "an editor moves pages and folders in the sidebar's tree", %{
    conn: conn,
    hanzo: hanzo,
    scope: scope,
    forge: forge,
    plans: plans,
    blade: blade
  } do
    {:ok, curve} = Pages.create(scope, %{"title" => "Notes on the curve", "space_id" => forge.id})
    {:ok, view, _html} = live(log_in_user(conn, hanzo), ~p"/")
    tree = "space-tree-#{forge.id}"

    assert Narabe.Test.outline(view, tree) == [
             {"Plans", 1},
             {"The last blade", 2},
             {"Notes on the curve", 1}
           ]

    Narabe.Test.move(view, tree, "page:#{curve.id}",
      parent: "folder:#{plans.id}",
      before: "page:#{blade.id}"
    )

    assert Narabe.Test.outline(view, tree) == [
             {"Plans", 1},
             {"Notes on the curve", 2},
             {"The last blade", 2}
           ]

    assert Pages.get!(scope, curve.id).folder_id == plans.id

    # The order stays as it was left, for everyone.
    {:ok, other, _html} = live(log_in_user(build_conn(), hanzo), ~p"/spaces/#{forge.id}")
    assert Narabe.Test.items(other, tree) == ["Plans", "Notes on the curve", "The last blade"]
  end

  test "a commenter's tree does not move", %{
    conn: conn,
    yuki: yuki,
    forge: forge,
    blade: blade,
    scope: scope
  } do
    {:ok, view, _html} = live(log_in_user(conn, yuki), ~p"/")
    assert has_element?(view, "#space-tree-#{forge.id}[data-config*='\"readonly\":true']")

    Narabe.Test.move(view, "space-tree-#{forge.id}", "page:#{blade.id}", parent: nil)
    refute is_nil(Pages.get!(scope, blade.id).folder_id)
  end

  test "a chart in a page reads live, and moves as its table's rows change", %{
    conn: conn,
    hanzo: hanzo,
    scope: scope,
    forge: forge
  } do
    {:ok, table} =
      Pages.create(scope, %{"title" => "Blades", "kind" => "table", "space_id" => forge.id})

    row =
      Notebook.Repo.insert!(%Notebook.Pages.Row{
        page_id: table.id,
        title: "Fold",
        status: "done",
        points: 5
      })

    {:ok, page} = Pages.create(scope, %{"title" => "Numbers", "space_id" => forge.id})
    {:ok, chart} = Notebook.Charts.create(scope, page, table, "points_by_status")

    body =
      Kotoba.Content.from_markdown("""
      <!-- kotoba:embed {"kind":"chart","ref":"#{chart.id}","title":"Points by status"} -->

      Points by status

      <!-- /kotoba:embed -->
      """)

    {:ok, page} = Pages.update(scope, page, %{"body" => body})

    {:ok, view, _html} = live(log_in_user(conn, hanzo), ~p"/pages/#{page.id}")
    assert has_element?(view, "#body-reader[data-readonly='true']")

    # The editor tells the page its embed's slot, as it does in the browser.
    view
    |> with_target("#body-reader-embeds")
    |> render_hook("kotoba:embeds", %{
      "action" => "mount",
      "slot" => "body-reader-embed-1",
      "kind" => "chart",
      "ref" => to_string(chart.id),
      "title" => "Points by status"
    })

    assert [%{"Points" => 5}] = chart_data(view, "body-reader-embed-1")

    # A row changes; the relay of its table (Charts.watch_rows/1, tested in
    # ChartsTest) tells the page.
    row |> Ecto.Changeset.change(points: 8) |> Notebook.Repo.update!()
    send(view.pid, {:chart_rows, table.id})
    assert [%{"Points" => 8}] = chart_data(view, "body-reader-embed-1")
  end

  test "the sidebar follows changes others make", %{
    conn: conn,
    hanzo: hanzo,
    scope: scope,
    forge: forge
  } do
    {:ok, view, _html} = live(log_in_user(conn, hanzo), ~p"/")
    {:ok, _} = Pages.create(scope, %{"title" => "Notes on the curve", "space_id" => forge.id})
    assert has_element?(view, "#sidebar .sidebar-page", "Notes on the curve")
  end

  test "an editor makes a team space, then a folder in it", %{conn: conn, hanzo: hanzo} do
    {:ok, view, _html} = live(log_in_user(conn, hanzo), ~p"/spaces/new")

    {:ok, view, _html} =
      view
      |> form("#space-form", space: %{name: "Tea house", description: "By the river."})
      |> render_submit()
      |> follow_redirect(log_in_user(build_conn(), hanzo))

    assert has_element?(view, ".member-list", "Hattori Hanzo")
    [tea] = Enum.filter(Spaces.list(Scope.for_user(hanzo)), &(&1.name == "Tea house"))

    {:ok, view, _html} = live(log_in_user(build_conn(), hanzo), ~p"/spaces/#{tea.id}")
    view |> element("button", "New folder") |> render_click()

    {:ok, _view, html} =
      view
      |> form("#folder-form", folder: %{name: "Menu"})
      |> render_submit()
      |> follow_redirect(log_in_user(build_conn(), hanzo))

    assert html =~ "Menu"
  end

  test "a commenter sees a space without its editing buttons", %{
    conn: conn,
    yuki: yuki,
    forge: forge
  } do
    {:ok, view, _html} = live(log_in_user(conn, yuki), ~p"/spaces/#{forge.id}")
    assert has_element?(view, ".folder-card", "Plans")
    refute has_element?(view, ".space-actions a", "New page")
    refute has_element?(view, "button", "New folder")
    refute has_element?(view, "a", "Members")
  end

  test "a commenter reads a page and may not edit it", %{conn: conn, yuki: yuki, blade: blade} do
    conn = log_in_user(conn, yuki)
    {:ok, view, _html} = live(conn, ~p"/pages/#{blade.id}")
    assert has_element?(view, ".breadcrumb", "The forge")
    assert has_element?(view, ".breadcrumb", "Plans")
    refute has_element?(view, ".reader-actions a", "Edit together")

    assert {:error, {:live_redirect, %{to: to}}} = live(conn, ~p"/pages/#{blade.id}/edit")
    assert to == ~p"/pages/#{blade.id}"
  end

  test "a page someone may not read is not there", %{conn: conn, hanzo: hanzo, yuki: yuki} do
    {:ok, letter} =
      Pages.create(Scope.for_user(hanzo), %{
        "title" => "A letter",
        "space_id" => Spaces.private!(hanzo).id
      })

    assert_raise Sekisho.Denied, fn -> live(log_in_user(conn, yuki), ~p"/pages/#{letter.id}") end
  end

  test "an admin manages the members", %{conn: conn, hanzo: hanzo, yuki: yuki, forge: forge} do
    {:ok, view, _html} = live(log_in_user(conn, hanzo), ~p"/spaces/#{forge.id}/members")
    [member] = Enum.filter(Spaces.members(forge), &(&1.user_id == yuki.id))

    view
    |> element("#member-#{member.id} form")
    |> render_change(%{"member_id" => member.id, "role" => "editor"})

    assert Enum.find(Spaces.members(forge), &(&1.user_id == yuki.id)).role == "editor"

    view |> element("#member-#{member.id} button", "Remove") |> render_click()
    refute Enum.any?(Spaces.members(forge), &(&1.user_id == yuki.id))
  end

  test "only admins open the members", %{conn: conn, yuki: yuki, forge: forge} do
    assert_raise Ecto.NoResultsError, fn ->
      live(log_in_user(conn, yuki), ~p"/spaces/#{forge.id}/members")
    end
  end

  test "a new page goes where it was asked for", %{
    conn: conn,
    hanzo: hanzo,
    forge: forge,
    plans: plans
  } do
    {:ok, view, _html} =
      live(log_in_user(conn, hanzo), ~p"/pages/new?space=#{forge.id}&folder=#{plans.id}")

    assert has_element?(view, "#page_place option[selected]", "The forge / Plans")

    view
    |> form("#new-page",
      page: %{title: "The naming of the blade", kind: "board", place: "#{forge.id}:#{plans.id}"}
    )
    |> render_submit()

    page = Enum.find(Pages.list(Scope.for_user(hanzo)), &(&1.title == "The naming of the blade"))
    assert {page.space_id, page.folder_id} == {forge.id, plans.id}
  end

  test "a page is archived, moved and restored from the palette", %{
    conn: conn,
    hanzo: hanzo,
    scope: scope,
    forge: forge,
    blade: blade
  } do
    {:ok, view, _html} = live(log_in_user(conn, hanzo), ~p"/pages/#{blade.id}")

    assert %{"ok" => true} = run(view, :archive_page)
    assert has_element?(view, ".archived-banner")
    refute has_element?(view, "#sidebar .sidebar-page", "The last blade")

    {:ok, archive, _html} = live(log_in_user(build_conn(), hanzo), ~p"/archive")
    assert has_element?(archive, "#archived-#{blade.id}")
    archive |> element("#archived-#{blade.id} button", "Restore") |> render_click()
    refute has_element?(archive, "#archived-#{blade.id}")

    {:ok, view, _html} = live(log_in_user(build_conn(), hanzo), ~p"/pages/#{blade.id}")
    assert %{"ok" => true} = run(view, "move-#{forge.id}-")
    assert %{space_id: space_id, folder_id: nil} = Pages.get!(scope, blade.id)
    assert space_id == forge.id
  end

  # The data of a chart in an embed's slot: LiveView renders the embed in a
  # portal (a <template>), whose content Fude.Test reads as its own page.
  defp chart_data(view, slot) do
    [_, content] =
      Regex.run(
        ~r/<template[^>]*data-phx-portal="##{slot}"[^>]*>(.*?)<\/template>/s,
        render(view)
      )

    Fude.Test.data(content, "chart-" <> slot)
  end
end
