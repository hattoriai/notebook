defmodule Notebook.AgentsOffLimitsTest do
  # Issho's documents (the agent's inbox) outlive a test: these run alone.
  use Notebook.DataCase, async: false

  import Notebook.AccountsFixtures

  alias Notebook.Accounts.Scope
  alias Notebook.{Agents, Collaboration, Pages, Search, Spaces}

  setup do
    hanzo = user_fixture(%{name: "Hattori Hanzo"})
    scope = Scope.for_user(hanzo)
    {:ok, agent, _token} = Agents.create(scope, %{"name" => "Hanzo's agent"})
    agent_scope = Scope.for_agent(hanzo, Agents.key(agent))
    {:ok, forge} = Spaces.create_team(scope, %{name: "The forge"})

    {:ok, journal} =
      Pages.create(scope, %{
        "title" => "Day one without steel",
        "space_id" => forge.id,
        "body" => Kotoba.Content.from_markdown("Woke at four. Lit nothing.")
      })

    {:ok, plans} =
      Pages.create(scope, %{"title" => "Plans for the forge", "space_id" => forge.id})

    # Each test's ids are the last one's (its rows are rolled back), and
    # Issho's documents outlive a test: none of the last one's goes on.
    for document <- [
          Issho.Inbox.document(Agents.key(agent)),
          Issho.Comments.document(Collaboration.room(journal))
        ] do
      case Issho.Documents.whereis(Notebook.Issho, document) do
        nil -> :ok
        pid -> GenServer.stop(pid)
      end
    end

    %{
      hanzo: hanzo,
      scope: scope,
      agent: agent,
      agent_scope: agent_scope,
      forge: forge,
      journal: journal,
      plans: plans
    }
  end

  defp titles(scope), do: scope |> Pages.list() |> Enum.map(& &1.title) |> Enum.sort()

  defp identity(hanzo, agent),
    do:
      Issho.Identity.new(%{id: Agents.key(agent), name: agent.name, kind: :agent},
        on_behalf_of: hanzo
      )

  test "a page off limits: its person still works there, their agent may not read, find or join it",
       %{
         hanzo: hanzo,
         scope: scope,
         agent: agent,
         agent_scope: agent_scope,
         journal: journal
       } do
    assert "Day one without steel" in titles(agent_scope)
    # Only its editors close it.
    assert {:error, _} = Pages.set_closed_to_agents(Scope.for_user(user_fixture()), journal, true)
    {:ok, journal} = Pages.set_closed_to_agents(scope, journal, true)
    assert Pages.closed_to_agents?(journal)

    # The person, as before.
    assert Pages.allowed?(scope, :edit, journal)
    assert "Day one without steel" in titles(scope)
    assert [_] = Search.search(scope, "lit nothing")
    room = Collaboration.room(journal)
    assert :ok = Collaboration.authorize(Issho.Identity.new(hanzo), room, :write)

    # Their agent: not there, by the same rules.
    refute Pages.allowed?(agent_scope, :read, journal)
    refute "Day one without steel" in titles(agent_scope)
    assert "Plans for the forge" in titles(agent_scope)
    assert [] = Search.search(agent_scope, "lit nothing")
    assert {:error, :forbidden} = Collaboration.authorize(identity(hanzo, agent), room, :join)
    assert {:error, :forbidden} = Collaboration.authorize(identity(hanzo, agent), room, :read)

    {:ok, _journal} = Pages.set_closed_to_agents(scope, journal, false)
    assert :ok = Collaboration.authorize(identity(hanzo, agent), room, :join)
  end

  test "a space off limits closes every page and folder in it to agents", %{
    scope: scope,
    agent_scope: agent_scope,
    forge: forge
  } do
    {:ok, folder} = Spaces.create_folder(scope, forge, %{name: "Ceremonies"})
    assert Spaces.allowed?(agent_scope, :read, forge)

    {:ok, _forge} = Spaces.set_closed_to_agents(scope, forge, true)
    forge = Notebook.Repo.get!(Spaces.Space, forge.id)
    refute Spaces.allowed?(agent_scope, :read, forge)
    refute Spaces.allowed?(agent_scope, :read, folder)
    assert titles(agent_scope) |> Enum.filter(&String.contains?(&1, "forge")) == []
    assert Spaces.allowed?(scope, :manage, forge)
    assert "Plans for the forge" in titles(scope)
  end

  test "what is said to an agent on a page off limits stays out of its inbox, until it opens", %{
    hanzo: hanzo,
    scope: scope,
    agent: agent,
    journal: journal
  } do
    {:ok, journal} = Pages.set_closed_to_agents(scope, journal, true)
    room = Collaboration.room(journal)
    key = Agents.key(agent)
    me = %{id: key, name: agent.name, kind: :agent}

    {:ok, _} =
      Issho.Comments.start(Notebook.Issho, room, hanzo, nil, "@Hanzo's agent, read this?",
        mentions: [key]
      )

    # The room's policy answers the inbox as it answers the room: closed,
    # nothing of the page; opened again, what was said there.
    assert {:ok, []} = Issho.Inbox.items(Notebook.Issho, me, on_behalf_of: hanzo)
    {:ok, _journal} = Pages.set_closed_to_agents(scope, journal, false)
    assert [%{"room" => ^room}] = inbox(me, hanzo)
  end

  defp inbox(agent, person, tries \\ 50) do
    case Issho.Inbox.items(Notebook.Issho, agent, on_behalf_of: person) do
      {:ok, [_ | _] = items} ->
        items

      _ when tries > 0 ->
        Process.sleep(10)
        inbox(agent, person, tries - 1)

      other ->
        other
    end
  end
end
