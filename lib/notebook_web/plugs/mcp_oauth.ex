defmodule NotebookWeb.Plugs.MCPOAuth do
  @moduledoc """
  The routes of the Notebook's OAuth server for MCP clients (discovery,
  tokens, consent) answer only when Notebook settings turn OAuth on
  (`Notebook.Agents.oauth?/0`): otherwise they are not found, and a
  client learns of no sign-in.
  """
  @behaviour Plug
  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if Notebook.Agents.oauth?(),
      do: conn,
      else: conn |> send_resp(404, "Not found") |> halt()
  end
end
