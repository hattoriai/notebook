defmodule NotebookWeb.AgentsLiveTest do
  use NotebookWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Notebook.AccountsFixtures

  setup %{conn: conn} do
    user = user_fixture(%{name: "Hattori Hanzo"})
    %{conn: log_in_user(conn, user), user: user}
  end

  test "a person connects an agent, sees its token once, and revokes it", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/agents")
    assert has_element?(view, "#agent-list", "No agent yet")
    assert has_element?(view, "#agent_name[value=\"Hattori Hanzo's agent\"]")

    view
    |> form("#agent-form", agent: %{name: "Claude, for Hanzo", lifetime: "30"})
    |> render_submit()

    assert has_element?(view, "#agent-connected", "Claude, for Hanzo is connected")

    url =
      view
      |> element("#agent-url")
      |> render()
      |> then(&Regex.run(~r/value="([^"]+)"/, &1))
      |> List.last()

    "nbk_" <> _ =
      token = url |> URI.parse() |> Map.get(:query) |> URI.decode_query() |> Map.get("token")

    assert has_element?(view, "#claude-command", token)

    [agent] = Notebook.Agents.active()
    assert has_element?(view, "#agent-#{agent.id}", "Claude, for Hanzo")

    # The MCP endpoint takes it, as the agent.
    assert Plug.Test.conn(:post, "/mcp?token=#{token}")
           |> NotebookWeb.AgentAuth.call([])
           |> Map.get(:assigns)
           |> Map.get(:sake_scope)
           |> Map.get(:id) == agent.id

    view |> element("#agent-#{agent.id} .agent-revoke") |> render_click()
    refute has_element?(view, "#agent-connected")
    assert has_element?(view, "#agent-list", "No agent yet")

    assert Plug.Test.conn(:post, "/mcp?token=#{token}")
           |> NotebookWeb.AgentAuth.call([])
           |> Map.get(:status) == 401
  end
end
