# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :notebook, :scopes,
  user: [
    default: true,
    module: Notebook.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: Notebook.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :notebook,
  ecto_repos: [Notebook.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :notebook, NotebookWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: NotebookWeb.ErrorHTML, json: NotebookWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Notebook.PubSub,
  live_view: [signing_salt: "BhLFyLvM"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  notebook: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{
      "NODE_PATH" => [
        Path.expand("../deps", __DIR__),
        Path.expand("../..", __DIR__),
        Mix.Project.build_path()
      ]
    }
  ],
  # The browser clients of the libraries taken from their GitHub main,
  # from their sources in deps/ (`mix notebook.libraries`), as each
  # builds its own: their ES modules, what `import "kotoba"` finds.
  issho: [
    args:
      ~w(src/index.ts --bundle --minify --target=es2020 --external:phoenix --format=esm --outfile=../priv/static/issho.esm.js),
    cd: Path.expand("../deps/issho/assets", __DIR__),
    env: %{"NODE_PATH" => nil}
  ],
  kotoba: [
    args:
      ~w(src/index.ts --bundle --minify --target=es2020 --conditions=production --define:process.env.NODE_ENV="production" --external:phoenix --external:phoenix_live_view --external:issho --format=esm --outfile=../priv/static/kotoba.esm.js),
    cd: Path.expand("../deps/kotoba/assets", __DIR__),
    env: %{"NODE_PATH" => nil}
  ],
  kotoba_collab: [
    args:
      ~w(src/collab/index.ts --bundle --minify --target=es2020 --conditions=production --define:process.env.NODE_ENV="production" --external:phoenix --external:phoenix_live_view --external:issho --format=esm --outfile=../priv/static/kotoba-collab.esm.js),
    cd: Path.expand("../deps/kotoba/assets", __DIR__),
    env: %{"NODE_PATH" => nil}
  ],
  hakushi: [
    args:
      ~w(src/index.ts --bundle --minify --target=es2020 --external:phoenix --external:phoenix_live_view --format=esm --outfile=../priv/static/hakushi.esm.js),
    cd: Path.expand("../deps/hakushi/assets", __DIR__),
    env: %{"NODE_PATH" => nil}
  ],
  masu: [
    args:
      ~w(src/index.ts --bundle --minify --target=es2020 --external:phoenix --external:phoenix_live_view --format=esm --outfile=../priv/static/masu.esm.js),
    cd: Path.expand("../deps/masu/assets", __DIR__),
    env: %{"NODE_PATH" => nil}
  ],
  kotoba_extensions: [
    args:
      ~w(js/kotoba/extensions/*.js --bundle --format=esm --target=es2022 --outdir=../priv/static/assets/kotoba/extensions),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  notebook: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Agents in the pages' rooms: who an MCP caller is (NotebookWeb.AgentAuth
# signs them in as the account they work for), and the tables they may use.
config :issho, Issho.MCP, instance: Notebook.Issho, agent: {NotebookWeb.MCP, :agent}

# The rows an agent's chart draws (read_chart): its table's, for whom may read it.
config :fude, Fude.Issho, data: {Notebook.Charts, :data}
config :masu, Masu.Issho, grids: {Notebook.Grids, :for_agent}

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason
config :swoosh, :api_client, false

config :kotoba, nodes: [Notebook.Kotoba.Nodes.Callout]

# An agent's files (attach_file): as large as a database record's.
config :kotoba, Kotoba.Issho, attach: [max_bytes: 25_000_000]

# Koyomi's pickers write dates for a reader in Lisbon: "today", the review
# times and the wall clock of the review picker are in this zone.
config :koyomi, locale: "en-GB", time_zone: "Europe/Lisbon"
config :elixir, :time_zone_database, Tz.TimeZoneDatabase

# SQLite takes one writer at a time: a transaction takes the lock when it
# begins, and a writer waits for it, rather than failing at once when two
# transactions that read would both write (the notifications write beside
# the change that made them).
config :notebook, Notebook.Repo, default_transaction_mode: :immediate, busy_timeout: 5_000

# The jobs of the notifications (Chime's emails, reminders and digests),
# in SQLite with the rest.
config :notebook, Oban,
  engine: Oban.Engines.Lite,
  notifier: Oban.Notifiers.PG,
  repo: Notebook.Repo,
  # Storage: one transfer of the files at a time (Notebook.Storage.Transfer).
  queues: [default: 10, storage: 1],
  plugins: [Oban.Plugins.Pruner]

# Who the notifications' emails are from.
config :notebook, :email_from, {"Notebook", "notebook@localhost"}

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
