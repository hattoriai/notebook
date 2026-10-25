defmodule NotebookWeb.AgentAuth do
  @moduledoc """
  Signs an MCP client in as the agent whose token it brings, made on the
  Agents page (`Notebook.Agents`): `Authorization: Bearer <token>`, or
  `?token=` in the URL (for clients that take only a URL). The agent,
  with its person, is the client's principal (`sake_scope`): it acts on
  their behalf.
  """
  @behaviour Plug
  import Plug.Conn

  @doc false
  # The secret of MCP sessions: of the endpoint's.
  def secret, do: NotebookWeb.Endpoint.config(:secret_key_base)

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    with token when is_binary(token) <- token_of(conn),
         {:ok, agent} <- Notebook.Agents.authenticate(token) do
      assign(conn, :sake_scope, agent)
    else
      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          401,
          ~s({"error":"Connect this agent on the Notebook's Agents page, and bring the token it gives. A token revoked or past its end works no more."})
        )
        |> halt()
    end
  end

  defp token_of(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] -> token
      _ -> conn |> fetch_query_params() |> Map.get(:query_params) |> Map.get("token")
    end
  end
end
