defmodule NotebookWeb.MCPEndpoint do
  @moduledoc """
  The Notebook's MCP endpoint (`NotebookWeb.MCP`), at `/mcp`.

  A client brings an agent's token, from the Agents page
  (`NotebookWeb.AgentAuth`): it is that agent. When Notebook settings turn
  OAuth on, a client may instead bring an access token from the
  Notebook's OAuth server (Sake's): its person signed in from the client,
  and each call acts as one of their agents (`NotebookWeb.MCP.Actors`).
  Without OAuth, a request with no agent's token is refused, and nothing
  tells a client to sign in.
  """
  @behaviour Plug

  alias Notebook.Agents
  alias NotebookWeb.AgentAuth

  @secret {AgentAuth, :secret, []}

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    cond do
      Agents.token?(AgentAuth.token_of(conn)) -> agent(conn)
      Agents.oauth?() -> serve(conn, auth: true)
      true -> AgentAuth.call(conn, [])
    end
  end

  defp agent(conn) do
    case AgentAuth.call(conn, []) do
      %Plug.Conn{halted: true} = conn -> conn
      conn -> serve(conn, [])
    end
  end

  defp serve(conn, opts),
    do: Sake.Plug.call(conn, Sake.Plug.init([server: NotebookWeb.MCP, secret: @secret] ++ opts))
end
