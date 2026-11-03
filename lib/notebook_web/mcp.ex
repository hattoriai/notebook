defmodule NotebookWeb.MCP do
  @moduledoc """
  The Notebook for MCP clients (Claude Code, Codex, any other): every tool
  of the pages, at `/mcp`. A client connects with an agent's token (the
  Agents page), and works on its person's behalf: in the pages' rooms it is an
  agent of its own, by the name its person gave it, the people see it,
  and the rooms' policy says what it may do.
  """
  use Issho.MCP,
    name: "notebook",
    version: "0.1.0",
    instructions:
      """
        The Notebook is a shared notebook of pages that people edit live. A page
        is a text (Kotoba), a board of notes and arrows (Hakushi) or a table of
        rows (Masu). Call list_pages first: it gives each page's room and the
        name its tools take. You are in the room with the people: they see your
        cursor, selection or pointer, and your changes as you make them. Say
        what you do with set_status, and work as a person would: select before
        you format, type where the caret is, move a note by dragging it.
        You have a memory of your own that lasts between sessions (the memory
        tool): begin with `cat self.md` there, what your person tells you to
        be, then look at what you noted before; note what you learn.
        You may be able to act as other identities of your person's: their
        agents, or a bot of the notebook's. list_actors says which; act_as
        takes one on (its name and persona), and then pass its id as `as`
        to every tool. Without `as`, you act as the default.
      """ <> Issho.MCP.instructions(),
    tools: Notebook.Tools.all()

  actors(NotebookWeb.MCP.Actors)

  alias Notebook.Accounts.User
  alias Notebook.Agents.Agent
  alias Notebook.Bots.Bot
  alias Sake.Actors.Actor

  @doc """
  Who an MCP call is in the pages' rooms: the actor it acts as
  (`NotebookWeb.MCP.Actors`).

    * An agent, by its own key and the name its person gave it, acting on
      behalf of that person: the rooms' policy and the tools treat it as
      they treat its person, and people see, mention and pause it by its
      name. A client with an agent's token is always that agent.
    * A bot of the notebook's, for an admin with OAuth: the bot itself,
      with only its own tools, as when it runs on its own (`Notebook.Bots`).
    * A person with OAuth who has no agent yet: an agent named for their
      client ("Claude Code"), on their behalf, without a memory.
  """
  def agent(%Sake.Context{actor: %Actor{data: %Agent{} = agent}}), do: agent_of(agent)

  def agent(%Sake.Context{actor: %Actor{data: %Bot{} = bot}}),
    do: {Notebook.Bots.actor(bot), only: Notebook.Bots.tool_names(bot)}

  def agent(%Sake.Context{scope: %Agent{} = agent}), do: agent_of(agent)

  def agent(%Sake.Context{scope: %User{} = user} = ctx) do
    case NotebookWeb.MCP.Actors.default(ctx) do
      %Actor{} = actor -> agent(%{ctx | actor: actor})
      nil -> client_agent(user, ctx)
    end
  end

  defp agent_of(%Agent{user: %User{} = user} = agent),
    do: {%{id: Notebook.Agents.key(agent), name: agent.name, kind: :agent}, on_behalf_of: user}

  defp client_agent(user, ctx) do
    client = ctx.client_info || %{}
    name = client["title"] || client["name"] || "Agent"
    {%{id: "agent:client-#{user.id}", name: name, kind: :agent}, on_behalf_of: user}
  end
end
