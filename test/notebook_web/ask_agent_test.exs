defmodule NotebookWeb.AskAgentTest do
  # A person asks their own agent about what they selected in a page's
  # text: privately, to an agent of theirs that may read the page.
  use NotebookWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Notebook.AccountsFixtures

  alias Notebook.Accounts.Scope
  alias Notebook.{Agents, Collaboration, Pages}

  setup %{conn: conn} do
    hanzo = user_fixture(%{name: "Hattori Hanzo"})
    ken = user_fixture(%{name: "Ken"})
    scope = Scope.for_user(hanzo)
    {:ok, page} = Pages.create(scope, %{"title" => "Plans"})
    {:ok, agent, _token} = Agents.create(scope, %{"name" => "Hanzo's apprentice"})
    {:ok, kens, _token} = Agents.create(Scope.for_user(ken), %{"name" => "Ken's agent"})

    # Each test's ids are the last one's (its rows are rolled back), and
    # Issho's documents outlive a test: none of the last one's goes on.
    for a <- [agent, kens] do
      case Issho.Documents.whereis(Notebook.Issho, Issho.Inbox.document(Agents.key(a))) do
        nil -> :ok
        pid -> GenServer.stop(pid)
      end
    end

    %{
      conn: log_in_user(conn, hanzo),
      hanzo: hanzo,
      scope: scope,
      page: page,
      agent: agent,
      kens: kens
    }
  end

  defp person(user), do: Issho.Identity.new(%{id: to_string(user.id), name: user.name})

  test "a person may ask their own agents, that may read the page", %{
    hanzo: hanzo,
    scope: scope,
    page: page,
    agent: agent,
    kens: kens
  } do
    room = Collaboration.room(page)
    assert :ok = Collaboration.ask(person(hanzo), room, Agents.key(agent))
    assert {:error, :forbidden} = Collaboration.ask(person(hanzo), room, Agents.key(kens))
    assert {:error, :forbidden} = Collaboration.ask(person(hanzo), room, "agent:nope")

    {:ok, _} = Pages.set_closed_to_agents(scope, page, true)
    assert {:error, :forbidden} = Collaboration.ask(person(hanzo), room, Agents.key(agent))
    {:ok, _} = Pages.set_closed_to_agents(scope, page, false)

    {:ok, _} = Agents.revoke(scope, agent.id)
    assert {:error, :forbidden} = Collaboration.ask(person(hanzo), room, Agents.key(agent))
  end

  test "Assist, then Ask: the agent finds what was asked, where, in its inbox", %{
    conn: conn,
    hanzo: hanzo,
    page: page,
    agent: agent
  } do
    {:ok, view, _html} = live(conn, ~p"/pages/#{page.id}/edit")

    render_hook(view, "kotoba:assist", %{
      "ref" => "r1",
      "action" => "ask",
      "text" => "Fold it, again and again",
      "place" => %{"block" => 1, "id" => "b1"}
    })

    assert view |> element("#ask-dialog") |> render() =~ "Fold it, again and again"

    view |> form("#ask-form", %{"question" => "Make this shorter"}) |> render_submit()
    refute has_element?(view, "#ask-dialog")

    me = %{id: Agents.key(agent), name: agent.name, kind: :agent}
    assert [item] = inbox(me, hanzo)
    room = Collaboration.room(page)

    assert %{
             "name" => "agent.asked",
             "room" => ^room,
             "data" => %{
               "text" => "Make this shorter",
               "place" => %{"at" => %{"node" => "b1"}, "label" => "Fold it, again and again"},
               "version" => version
             }
           } = item

    assert is_binary(version)
  end

  test "with no agent, the person is told to connect one", %{
    conn: conn,
    scope: scope,
    page: page,
    agent: agent
  } do
    {:ok, _} = Agents.revoke(scope, agent.id)
    {:ok, view, _html} = live(conn, ~p"/pages/#{page.id}/edit")
    render_hook(view, "kotoba:assist", %{"ref" => "r1", "action" => "ask", "text" => "x"})
    refute has_element?(view, "#ask-dialog")
    assert render(view) =~ "Connect an agent first"
  end

  defp inbox(agent, person, tries \\ 50) do
    case Issho.Inbox.items(Notebook.Issho, agent, on_behalf_of: person) do
      {:ok, [_ | _] = items} -> items
      _ when tries > 0 -> Process.sleep(10) && inbox(agent, person, tries - 1)
      other -> other
    end
  end
end
