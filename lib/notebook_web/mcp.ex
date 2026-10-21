defmodule NotebookWeb.MCP do
  @moduledoc """
  The Notebook for MCP clients (Claude Code, Codex, any other): every tool
  of the pages, at `/mcp`. A client connects with its person's token (the
  Agents page), and works on their behalf: in the pages' rooms it is an
  agent named for the client, the people see it, and the rooms' policy
  says what it may do.
  """
  use Issho.MCP,
    name: "notebook",
    version: "0.1.0",
    instructions: """
      The Notebook is a shared notebook of pages that people edit live. A page
      is a text (Kotoba), a board of notes and arrows (Hakushi) or a table of
      rows (Masu). Call list_pages first: it gives each page's room and the
      name its tools take. You are in the room with the people: they see your
      cursor, selection or pointer, and your changes as you make them. Say
      what you do with set_status, and work as a person would: select before
      you format, type where the caret is, move a note by dragging it.
    """,
    tools: Notebook.Tools.all()
end
