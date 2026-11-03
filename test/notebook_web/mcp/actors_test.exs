defmodule NotebookWeb.MCP.ActorsTest do
  use Notebook.DataCase, async: false

  import Sake.Test
  import Notebook.AccountsFixtures

  alias Notebook.Accounts.Scope
  alias Notebook.{Agents, Bots}
  alias Sake.Client.ToolResult

  setup do
    admin = user_fixture(%{name: "Hattori Hanzo", admin: true})
    yuki = user_fixture(%{name: "Yuki Hattori"})

    {:ok, scribe, _token} =
      Agents.create(Scope.for_user(admin), %{"name" => "Scribe", "lifetime" => "90"})

    {:ok, scribe} =
      scribe |> Agents.Agent.changeset(%{"instructions" => "You write plainly."}) |> Repo.update()

    {:ok, critic, _token} =
      Agents.create(Scope.for_user(admin), %{"name" => "Critic", "lifetime" => "90"})

    {:ok, yukis, _token} =
      Agents.create(Scope.for_user(yuki), %{"name" => "Yuki's agent", "lifetime" => "90"})

    {:ok, gardener} =
      Bots.create(Scope.for_user(admin), %{
        "name" => "Gardener",
        "instructions" => "Tidy the tags."
      })

    %{admin: admin, yuki: yuki, scribe: scribe, critic: critic, yukis: yukis, gardener: gardener}
  end

  defp ids(client) do
    {:ok, %ToolResult{structured: %{"actors" => actors}}} = call_tool(client, "list_actors")
    Enum.map(actors, & &1["id"])
  end

  test "a person with OAuth may act as each of their agents, and an admin as the bots", %{
    admin: admin,
    yuki: yuki,
    scribe: scribe,
    critic: critic,
    gardener: gardener
  } do
    ids = admin |> then(&connect(NotebookWeb.MCP, scope: &1)) |> ids()

    assert Enum.sort(ids) ==
             Enum.sort([Agents.key(scribe), Agents.key(critic), Bots.key(gardener)])

    # No admin, no bots: only their own agent.
    assert [_one] = yuki |> then(&connect(NotebookWeb.MCP, scope: &1)) |> ids()
  end

  test "act_as gives an agent's persona, and `as` acts as it", %{admin: admin, scribe: scribe} do
    client = connect(NotebookWeb.MCP, scope: admin)

    assert {:ok,
            %ToolResult{structured: %{"name" => "Scribe", "instructions" => "You write plainly."}}} =
             call_tool(client, "act_as", %{"id" => Agents.key(scribe)})

    # The memory is the actor's own: an agent has one, a bot does not.
    assert {:ok, %ToolResult{is_error: false}} =
             call_tool(client, "memory", %{"command" => "ls", "as" => Agents.key(scribe)})
  end

  test "a bot acts with only its own tools", %{admin: admin, gardener: gardener} do
    client = connect(NotebookWeb.MCP, scope: admin)

    assert {:ok, %ToolResult{is_error: true}} =
             call_tool(client, "memory", %{"command" => "ls", "as" => Bots.key(gardener)})
  end

  test "no one acts as an agent or a bot that is not theirs", %{
    yuki: yuki,
    scribe: scribe,
    gardener: gardener
  } do
    client = connect(NotebookWeb.MCP, scope: yuki)

    for as <- [Agents.key(scribe), Bots.key(gardener), "agent:nope"] do
      assert {:ok, %ToolResult{is_error: true, text: "You may not act as" <> _}} =
               call_tool(client, "memory", %{"command" => "ls", "as" => as})
    end
  end

  test "a revoked agent is no one's to act as", %{admin: admin, critic: critic} do
    {:ok, _} = Agents.revoke(Scope.for_user(admin), critic.id)
    client = connect(NotebookWeb.MCP, scope: admin)

    refute Agents.key(critic) in ids(client)

    assert {:ok, %ToolResult{is_error: true}} =
             call_tool(client, "memory", %{"command" => "ls", "as" => Agents.key(critic)})
  end

  test "a client with an agent's token is that agent, and only it", %{
    scribe: scribe,
    critic: critic
  } do
    agent = Repo.preload(scribe, :user)
    client = connect(NotebookWeb.MCP, scope: agent)

    assert ids(client) == [Agents.key(scribe)]

    assert {:ok, %ToolResult{is_error: true}} =
             call_tool(client, "memory", %{"command" => "ls", "as" => Agents.key(critic)})

    assert {:ok, %ToolResult{is_error: false}} = call_tool(client, "memory", %{"command" => "ls"})
  end
end
