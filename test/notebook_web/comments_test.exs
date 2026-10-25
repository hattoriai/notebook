defmodule NotebookWeb.CommentsTest do
  # A page's comments and its agents at work, and what is said to an agent
  # while it is away: Issho's, in the Notebook.
  use NotebookWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Notebook.{Accounts, Pages, Repo}
  alias Notebook.Accounts.Scope

  setup %{conn: conn} do
    {:ok, nina} =
      Accounts.register_user(%{
        name: "Nina Writer",
        email: "nina@example.test",
        password: "long enough password"
      })

    {:ok, ada} =
      Accounts.register_user(%{
        name: "Ada Lovelace",
        email: "ada@example.test",
        password: "long enough password"
      })

    {:ok, page} = Pages.create(Scope.for_user(nina), %{title: "Plans"})

    {:ok, ada_agent, _token} =
      Notebook.Agents.create(Scope.for_user(ada), %{"name" => "Ada's agent"})

    {:ok, nina_agent, _token} =
      Notebook.Agents.create(Scope.for_user(nina), %{"name" => "Nina's agent"})

    # Each test's ids are the last one's (its rows are rolled back), and
    # Issho's documents outlive a test: none of the last one's goes on.
    for agent <- [nina_agent, ada_agent] do
      stop(Issho.Inbox.document(Notebook.Agents.key(agent)))
    end

    stop(Issho.Comments.document(Notebook.Collaboration.room(page)))

    %{
      conn: log_in_user(conn, nina),
      nina: nina,
      ada: ada,
      page: page,
      ada_agent: ada_agent,
      nina_agent: nina_agent
    }
  end

  defp stop(document) do
    case Issho.Documents.whereis(Notebook.Issho, document) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end
  end

  test "a page has its comments in a drawer, and its agents at work", %{conn: conn, page: page} do
    {:ok, view, _html} = live(conn, ~p"/pages/#{page.id}")

    assert has_element?(view, "#comments-toggle[aria-controls=comments-drawer]")
    assert has_element?(view, "#comments-drawer #page-comments")
    assert has_element?(view, "#page-agents[phx-hook=IsshoAgents]")
  end

  test "a comment may mention every account, and every agent by its name", %{
    conn: conn,
    page: page,
    ada: ada,
    ada_agent: ada_agent,
    nina_agent: nina_agent
  } do
    {:ok, view, _html} = live(conn, ~p"/pages/#{page.id}")

    candidates =
      view
      |> element("#page-comments")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.attribute("data-mentionable")
      |> hd()
      |> JSON.decode!()

    names = Map.new(candidates, &{&1["key"], &1["name"]})
    assert names[to_string(ada.id)] == "Ada Lovelace"
    assert names[Notebook.Agents.key(ada_agent)] == "Ada's agent"
    assert names[Notebook.Agents.key(nina_agent)] == "Nina's agent"
  end

  test "what is said to an agent waits in its inbox, kept in the database", %{
    page: page,
    nina: nina,
    ada: ada,
    ada_agent: ada_agent
  } do
    room = Notebook.Collaboration.room(page)
    agent = Notebook.Agents.key(ada_agent)

    {:ok, _} =
      Issho.Comments.start(Notebook.Issho, room, nina, nil, "@Ada's agent, a look?",
        mentions: [agent]
      )

    assert [%{"room" => ^room, "data" => %{"body" => "@Ada's agent, a look?"}}] =
             inbox(%{id: agent, name: "Ada's agent", kind: :agent}, ada)

    assert Repo.get(Notebook.IsshoStore.Document, Issho.Inbox.document(agent))
  end

  test "an MCP client is the agent whose token it has, by its own key, for its person", %{
    ada: ada,
    ada_agent: ada_agent
  } do
    ctx = %Sake.Context{
      scope: %{ada_agent | user: ada},
      client_info: %{"name" => "codex", "title" => "Codex"}
    }

    key = Notebook.Agents.key(ada_agent)

    assert {%{id: ^key, name: "Ada's agent", kind: :agent}, on_behalf_of: ^ada} =
             NotebookWeb.MCP.agent(ctx)

    assert NotebookWeb.MCP.__sake__(:instructions) =~ "inbox tool"
  end

  # The agent's inbox once the comment is delivered: delivery runs apart
  # from the comment.
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
