defmodule NotebookWeb.PublicLiveTest do
  # SQLite takes one writer at a time: these write a lot, so they run alone.
  use NotebookWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Notebook.AccountsFixtures

  alias Notebook.Accounts.Scope
  alias Notebook.{Pages, Publishing, Spaces}

  setup %{conn: conn} do
    hanzo = user_fixture(%{name: "Hattori Hanzo"})
    scope = Scope.for_user(hanzo)
    {:ok, forge} = Spaces.create_team(scope, %{name: "The forge"})
    {:ok, journal} = Spaces.create_folder(scope, forge, %{name: "Journal"})

    {:ok, day} =
      Pages.create(scope, %{
        "title" => "Day one without steel",
        "space_id" => forge.id,
        "folder_id" => journal.id,
        "body" => Kotoba.Content.from_markdown("Woke at four, as always. Lit nothing.")
      })

    {:ok, journal} = Publishing.publish(scope, journal)
    {:ok, day} = Publishing.publish(scope, day)
    on_exit(fn -> Application.delete_env(:notebook, :publishing) end)

    %{conn: conn, hanzo: hanzo, scope: scope, journal: journal, day: day}
  end

  test "anyone reads a published page, live as it is saved", %{conn: conn, scope: scope, day: day} do
    {:ok, view, html} = live(conn, "/hanzo/journal/day-one-without-steel")
    assert html =~ "Day one without steel"
    assert html =~ "Woke at four"
    assert html =~ ~s(rel="canonical" href="#{Publishing.url(day)}")

    {:ok, _} = Pages.publish(scope, day, Kotoba.Content.from_markdown("Woke at five, for once."))
    assert render(view) =~ "Woke at five"
  end

  test "a blog lists its posts, and has a feed", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/hanzo/journal")
    assert html =~ "Journal"
    assert html =~ "Day one without steel"
    assert html =~ "/hanzo/journal/feed.xml"

    conn = get(conn, "/hanzo/journal/feed.xml")
    assert response_content_type(conn, :xml) =~ "rss"
    assert response(conn, 200) =~ "<title>Day one without steel</title>"
  end

  test "a person's handle lists what they published", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/hanzo")
    assert html =~ "Hattori Hanzo"
    assert html =~ "Journal"
  end

  test "an old path goes to the page's path, and nothing is a 404", %{conn: conn} do
    assert {:error, {:redirect, %{to: to}}} = live(conn, "/hanzo/day-one-without-steel")
    assert to =~ "/hanzo/journal/day-one-without-steel"

    assert_raise NotebookWeb.NotFound, fn -> live(conn, "/hanzo/nothing-here") end
  end

  test "a page taken back is no one's", %{conn: conn, scope: scope, day: day} do
    {:ok, _} = Publishing.unpublish(scope, day)

    assert_raise NotebookWeb.NotFound, fn ->
      live(conn, "/hanzo/journal/day-one-without-steel")
    end
  end

  test "under a prefix, as a site's proxy sends it", %{conn: conn} do
    Application.put_env(:notebook, :publishing, url: "https://hattori.ai", prefix: "/libs")
    {:ok, _view, html} = live(conn, "/libs/hanzo/journal/day-one-without-steel")
    assert html =~ ~s(href="https://hattori.ai/libs/hanzo/journal/day-one-without-steel")
    # Its styles, scripts and live socket at the notebook's own address.
    assert html =~ ~s(content="#{NotebookWeb.Endpoint.url()}/public/live")
    assert html =~ NotebookWeb.Endpoint.static_url() <> "/assets/"
  end

  test "an editor publishes a page from its bar", %{conn: conn, hanzo: hanzo, scope: scope} do
    {:ok, page} =
      Pages.create(scope, %{"title" => "Kotoba", "space_id" => Spaces.private!(hanzo).id})

    {:ok, view, _html} = live(log_in_user(conn, hanzo), ~p"/pages/#{page.id}")

    view |> element("#publish-open") |> render_click()
    assert has_element?(view, ".publish-dialog", "Publish Kotoba")
    view |> form(".publish-form", %{slug: "kotoba"}) |> render_submit()
    assert has_element?(view, ".publish-live", "Published")
    assert has_element?(view, "#publish-open", "Published")
    assert Publishing.resolve(["hanzo", "kotoba"]) |> elem(0) == :page
  end
end
