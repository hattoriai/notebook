defmodule NotebookWeb.AgentAuth do
  @moduledoc """
  Signs an MCP client in as the person whose token it brings, from the
  Agents page: `Authorization: Bearer <token>`, or `?token=` in the URL
  (for clients that take only a URL). The person is the client's
  principal (`sake_scope`): its agent acts on their behalf.
  """
  @behaviour Plug
  import Plug.Conn

  alias Notebook.Accounts.User
  alias Notebook.Repo

  @salt "notebook agent"

  @doc "A person's token for their agents. It lasts until the app's secret changes."
  def token(%User{id: id}), do: Phoenix.Token.sign(NotebookWeb.Endpoint, @salt, id)

  @doc false
  # The secret of MCP sessions: of the endpoint's.
  def secret, do: NotebookWeb.Endpoint.config(:secret_key_base)

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    with token when is_binary(token) <- token_of(conn),
         {:ok, id} <- Phoenix.Token.verify(NotebookWeb.Endpoint, @salt, token, max_age: :infinity),
         %User{} = user <- Repo.get(User, id) do
      assign(conn, :sake_scope, user)
    else
      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, ~s({"error":"Bring your token from the Notebook's Agents page."}))
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
