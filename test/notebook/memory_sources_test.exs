defmodule Notebook.MemorySourcesTest do
  # Agents in rooms are processes of the node: these run alone.
  use Notebook.DataCase, async: false

  import Notebook.AccountsFixtures

  alias Notebook.Accounts.Scope
  alias Notebook.{Agents, Collaboration, Memory, Pages, Spaces}
  alias Notebook.Memory.Shell

  setup do
    hanzo = user_fixture(%{name: "Hattori Hanzo"})
    scope = Scope.for_user(hanzo)
    {:ok, agent, _token} = Agents.create(scope, %{"name" => "Hanzo's apprentice"})
    {:ok, forge} = Spaces.create_team(scope, %{name: "The forge"})

    {:ok, journal} =
      Pages.create(scope, %{"title" => "Day one without steel", "space_id" => forge.id})

    {:ok, plans} = Pages.create(scope, %{"title" => "Plans", "space_id" => forge.id})
    agent_scope = Scope.for_agent(hanzo, Agents.key(agent))

    %{
      hanzo: hanzo,
      scope: scope,
      agent: agent,
      agent_scope: agent_scope,
      journal: journal,
      plans: plans
    }
  end

  defp sh(agent, scope, command, sources \\ []),
    do: Shell.run(agent.id, command, scope: scope, sources: sources)

  test "a note learned on a page off limits is not there for the agent, until it opens", %{
    scope: scope,
    agent: agent,
    agent_scope: agent_scope,
    journal: journal,
    plans: plans
  } do
    sh(agent, agent_scope, "mkdir -p pages && echo '- woke at four' > pages/journal.md", [
      journal.id
    ])

    sh(agent, agent_scope, "echo '- steps joined by then' > pages/plans.md", [plans.id])
    # A file keeps every page it was written from.
    sh(agent, agent_scope, "echo '- and the forge is cold' >> pages/journal.md", [plans.id])

    assert Enum.sort(Memory.get(agent.id, "/pages/journal.md").sources) ==
             Enum.sort([journal.id, plans.id])

    {:ok, _} = Pages.set_closed_to_agents(scope, journal, true)

    assert %{"stdout" => "plans.md\n"} = sh(agent, agent_scope, "ls pages")
    assert %{"exit_code" => 1} = sh(agent, agent_scope, "cat pages/journal.md")
    assert %{"stdout" => ""} = sh(agent, agent_scope, "grep -rn 'woke' .")

    assert %{"stdout" => "pages/plans.md\n"} =
             sh(agent, agent_scope, "find pages -name '*.md'")

    # Not overwritten, not removed: what is hidden is its person's to see.
    assert %{"exit_code" => 1, "stderr" => stderr} =
             sh(agent, agent_scope, "echo mine > pages/journal.md")

    # just_bash says "Permission denied" for a redirection, whatever the reason.
    assert stderr =~ "Permission denied"
    assert %{"exit_code" => 0} = sh(agent, agent_scope, "rm -r pages")
    assert Memory.get(agent.id, "/pages/journal.md").content =~ "woke at four"
    assert Memory.get(agent.id, "/pages/plans.md") == nil

    {:ok, _} = Pages.set_closed_to_agents(scope, journal, false)

    assert %{"stdout" => "- woke at four\n- and the forge is cold\n"} =
             sh(agent, agent_scope, "cat pages/journal.md")
  end

  test "its person may let it see a hidden note again", %{
    scope: scope,
    agent: agent,
    agent_scope: agent_scope,
    journal: journal
  } do
    sh(agent, agent_scope, "echo '- woke at four' > journal.md", [journal.id])
    {:ok, _} = Pages.set_closed_to_agents(scope, journal, true)
    assert MapSet.member?(Memory.hidden(agent.id, agent_scope), "/journal.md")

    :ok = Memory.forget_sources(agent.id, "/journal.md")
    assert %{"stdout" => "- woke at four\n"} = sh(agent, agent_scope, "cat journal.md")
  end

  test "the memory tool notes the pages whose rooms the agent is in", %{
    hanzo: hanzo,
    agent: agent,
    plans: plans
  } do
    actor = %{id: Agents.key(agent), name: agent.name, kind: :agent}

    # In the room as Issho.Agents.rooms/2 sees it (its name in :global),
    # without the room's processes, which would outlive the test.
    stand_in = spawn(fn -> receive do: (:stop -> :ok) end)
    name = {Issho.Agents, Notebook.Issho, Agents.key(agent), Collaboration.room(plans)}
    :yes = :global.register_name(name, stand_in)
    on_exit(fn -> send(stand_in, :stop) end)

    ctx = Issho.Tool.Context.new(Notebook.Issho, actor, on_behalf_of: hanzo)

    assert {:ok, %{"exit_code" => 0}} =
             Notebook.Tools.Memory.call(%{command: "echo '- then' > plans.md"}, ctx)

    :global.unregister_name(name)

    assert Memory.get(agent.id, "/plans.md").sources == [plans.id]
  end
end
