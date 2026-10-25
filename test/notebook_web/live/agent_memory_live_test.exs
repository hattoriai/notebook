defmodule NotebookWeb.AgentMemoryLiveTest do
  use NotebookWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Notebook.AccountsFixtures

  alias Notebook.Accounts.Scope
  alias Notebook.{Agents, Memory}

  setup %{conn: conn} do
    hanzo = user_fixture(%{name: "Hattori Hanzo"})
    {:ok, agent, _token} = Agents.create(Scope.for_user(hanzo), %{"name" => "Hanzo's apprentice"})
    %{conn: log_in_user(conn, hanzo), agent: agent}
  end

  test "its person writes what it is, and sees what it notes as it notes it", %{
    conn: conn,
    agent: agent
  } do
    {:ok, view, _html} = live(conn, ~p"/agents/#{agent.id}")
    assert has_element?(view, "#memory-file", "/memories/self.md")

    view |> form("#memory-form", content: "Speak plainly.") |> render_submit()
    assert %{"stdout" => "Speak plainly."} = Memory.Shell.run(agent.id, "cat self.md")

    Memory.Shell.run(agent.id, "mkdir -p people && echo '- bold summaries' > people/hanzo.md")
    assert has_element?(view, "#memory-tree", "hanzo.md")

    view |> element("#memory-tree a", "hanzo.md") |> render_click()
    assert has_element?(view, "#memory-file textarea", "- bold summaries")
    view |> form("#memory-form", content: "- bold summaries, at the top\n") |> render_submit()
    assert Memory.get(agent.id, "/people/hanzo.md").content == "- bold summaries, at the top\n"

    view |> element("#memory-file .agent-revoke") |> render_click()
    assert Memory.get(agent.id, "/people/hanzo.md") == nil
    refute has_element?(view, "#memory-tree", "hanzo.md")
  end

  test "a note shows where it was learned, and one hidden from the agent says so", %{
    conn: conn,
    agent: agent
  } do
    hanzo = Notebook.Repo.get!(Notebook.Accounts.User, agent.user_id)
    scope = Scope.for_user(hanzo)

    {:ok, page} =
      Notebook.Pages.create(scope, %{
        "title" => "Letters I never sent",
        "space_id" => Notebook.Spaces.private!(hanzo).id
      })

    {:ok, _} = Memory.write(agent.id, "/letters.md", "- to the museum: no\n", [page.id])
    {:ok, _} = Notebook.Pages.set_closed_to_agents(scope, page, true)

    {:ok, view, _html} = live(conn, ~p"/agents/#{agent.id}?file=/letters.md")
    assert has_element?(view, "#memory-sources a", "Letters I never sent")
    assert has_element?(view, "#memory-tree .is-hidden", "letters.md")
    assert has_element?(view, "#memory-hidden")

    view |> element("#memory-hidden button") |> render_click()
    refute has_element?(view, "#memory-hidden")
    refute has_element?(view, "#memory-sources")
  end

  test "another's agent's memory is not there", %{agent: agent} do
    other = log_in_user(build_conn(), user_fixture(%{name: "Yuki Hattori"}))
    assert {:error, {:live_redirect, %{to: "/agents"}}} = live(other, ~p"/agents/#{agent.id}")
  end
end
