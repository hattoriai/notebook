defmodule NotebookWeb.AgentsOffLimitsLiveTest do
  use NotebookWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Notebook.AccountsFixtures

  alias Notebook.Accounts.Scope
  alias Notebook.{Agents, Pages, Spaces}

  setup %{conn: conn} do
    hanzo = user_fixture(%{name: "Hattori Hanzo"})
    scope = Scope.for_user(hanzo)
    {:ok, _agent, _token} = Agents.create(scope, %{"name" => "Hanzo's agent"})
    {:ok, forge} = Spaces.create_team(scope, %{name: "The forge"})

    {:ok, page} =
      Pages.create(scope, %{"title" => "Letters I never sent", "space_id" => forge.id})

    %{conn: log_in_user(conn, hanzo), scope: scope, forge: forge, page: page}
  end

  test "an editor closes a page to agents from its Share dialog", %{conn: conn, page: page} do
    {:ok, view, _html} = live(conn, ~p"/pages/#{page.id}")
    refute has_element?(view, "#agents-closed")
    assert render(view) =~ "Hanzo&#39;s agent"

    view |> element("#share-open") |> render_click()
    assert has_element?(view, ".share-agents", "May work here")
    view |> form(".share-agents", agents: "closed") |> render_change()

    assert has_element?(view, ".share-agents", "Off limits")
    assert has_element?(view, "#agents-closed", "No agents")
    assert Notebook.Repo.get!(Pages.Page, page.id).closed_to_agents
    # Nobody mentions an agent where none would read it.
    refute render(view) =~ "Hanzo&#39;s agent"
  end

  test "a space's admin closes it to agents, and its pages show it", %{
    conn: conn,
    forge: forge,
    page: page
  } do
    {:ok, view, _html} = live(conn, ~p"/spaces/#{forge.id}")
    view |> element("#space-agents") |> render_click()
    assert has_element?(view, "#space-agents", "Off limits to agents")
    assert Notebook.Repo.get!(Spaces.Space, forge.id).closed_to_agents

    {:ok, page_view, _html} = live(conn, ~p"/pages/#{page.id}")
    assert has_element?(page_view, "#agents-closed")
    page_view |> element("#share-open") |> render_click()
    assert has_element?(page_view, ".share-agents select[disabled]")
    assert has_element?(page_view, ".share-agents", "Its space is off limits to agents.")
  end
end
