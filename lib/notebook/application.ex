defmodule Notebook.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      NotebookWeb.Telemetry,
      Notebook.Repo,
      # The key of the notebook's secrets (Notebook.Secrets).
      Notebook.Vault,
      # Where the files are kept (this disk, or a bucket), as the admins chose.
      Notebook.Storage,
      {DNSCluster, query: Application.get_env(:notebook, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Notebook.PubSub},
      # The notifications (Chime): the feed, and the jobs of the rest; and
      # what notifies of the changes, one after the other.
      {Oban, Application.fetch_env!(:notebook, Oban)},
      {Chime, Notebook.Notifications.config()},
      Notebook.Notifications.Queue,
      # The pages' rooms: their people, their shared text and boards, and
      # Issho's own documents (comments, inboxes) in the database.
      {
        Issho,
        # A bot's inbox wakes it (Notebook.Bots).
        name: Notebook.Issho,
        pubsub: Notebook.PubSub,
        endpoint: NotebookWeb.Endpoint,
        policy: Notebook.Collaboration,
        store: {Notebook.IsshoStore, Notebook.Repo},
        on_mention: {Notebook.Bots, :wake}
      },
      # MCP for agents (/mcp): its streams and tasks, on every node.
      {Sake, secret_key_base: {NotebookWeb.AgentAuth, :secret, []}, pubsub: Notebook.PubSub},
      # Start a worker by calling: Notebook.Worker.start_link(arg)
      # {Notebook.Worker, arg},
      # Start to serve requests, typically the last entry
      NotebookWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Notebook.Supervisor]

    with {:ok, pid} <- Supervisor.start_link(children, opts) do
      Notebook.Notifications.attach()
      {:ok, pid}
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    NotebookWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
