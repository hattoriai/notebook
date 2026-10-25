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
      """ <> Issho.MCP.instructions(),
    tools: Notebook.Tools.all()

  @doc """
  Who an MCP caller is in the pages' rooms: the agent whose token it
  connected with (`Notebook.Agents`), by its own key and the name its
  person gave it, acting on behalf of that person. The rooms' policy and
  the tools treat it as they treat its person; people see, mention and
  pause it by its name.
  """
  def agent(%Sake.Context{
        scope: %Notebook.Agents.Agent{user: %Notebook.Accounts.User{} = user} = agent
      }),
      do: {%{id: Notebook.Agents.key(agent), name: agent.name, kind: :agent}, on_behalf_of: user}
end
