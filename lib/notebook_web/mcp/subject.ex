defmodule NotebookWeb.MCP.Subject do
  @moduledoc """
  Who an MCP client acts for when it connects with OAuth (Sake's OAuth
  server, when Notebook settings turn it on): the person who signed in to
  the Notebook from their client and approved it. Each call acts as one of
  their agents, or a bot for an admin (`NotebookWeb.MCP.Actors`).

  Each request loads the person again: a person removed, or a notebook
  whose OAuth is turned off, refuses the client at its next refresh, and
  turning it off refuses every request at once (`NotebookWeb.AgentAuth`).
  """
  @behaviour Sake.Auth.Subject

  alias Notebook.Accounts.{Scope, User}
  alias Notebook.Repo

  @impl true
  def from_conn(conn) do
    case conn.assigns[:current_scope] do
      %Scope{user: %User{bot: false} = user} -> {:ok, user}
      _ -> :error
    end
  end

  @impl true
  def id(%User{id: id}), do: "user:#{id}"

  @impl true
  def fetch("user:" <> id) do
    with {id, ""} <- Integer.parse(id),
         %User{bot: false} = user <- Repo.get(User, id) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  def fetch(_id), do: :error

  @impl true
  def display(%User{name: name}), do: name

  # Only while the notebook takes OAuth: turned off, no client is
  # authorized, and no grant is refreshed.
  @impl true
  def authorize_resource?(%User{}, _resource), do: Notebook.Agents.oauth?()

  @doc "The URL of the Notebook's OAuth server: the Notebook's own address."
  def issuer do
    config = Application.get_env(:notebook, NotebookWeb.Endpoint, [])
    url = config[:url] || []
    scheme = to_string(url[:scheme] || "http")
    host = url[:host] || "localhost"
    port = url[:port] || if(scheme == "http", do: get_in(config, [:http, :port]))

    case {scheme, port} do
      {_, nil} -> "#{scheme}://#{host}"
      {"https", 443} -> "https://#{host}"
      {"http", 80} -> "http://#{host}"
      {_, port} -> "#{scheme}://#{host}:#{port}"
    end
  end

  @doc "The options of Sake's OAuth server, for the application's `{Sake, auth: ...}`."
  def auth_options do
    issuer = issuer()

    [
      subject: __MODULE__,
      issuer: issuer,
      servers: [NotebookWeb.MCP],
      store: {Sake.Auth.Store.Ecto, repo: Repo},
      resources: ["/mcp"],
      consent: NotebookWeb.MCP.Consent,
      allow_insecure: String.starts_with?(issuer, "http://")
    ]
  end
end
