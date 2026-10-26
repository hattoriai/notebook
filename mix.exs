defmodule Notebook.MixProject do
  use Mix.Project

  def project do
    [
      app: :notebook,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Notebook.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:bcrypt_elixir, "~> 3.0"},
      {:phoenix, "~> 1.8.14"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:ecto_sqlite3, "~> 0.25"},
      # The notebook's secrets (a bucket's key, and those to come), encrypted
      # in the database with keys that rotate. Only AES-GCM and the Binary
      # type: hex.audit's advisories for cloak 1.1.4 (AES-CTR) and cloak_ecto
      # 1.3.0 (the PBKDF2 field) are of parts the notebook does not use.
      {:cloak_ecto, "~> 1.3"},
      # The agents' memory: a bash of their own, over files kept in the
      # database (Notebook.Memory).
      {:just_bash, "~> 0.4.0"},
      {:swoosh, "~> 1.18"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.5", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:daisyui,
       github: "saadeghi/daisyui",
       tag: "v5.5.20",
       sparse: "packages/bundle",
       app: false,
       compile: false,
       depth: 1},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:issho, "~> 0.5"},
      {:kotoba, "~> 0.9"},
      {:hakushi, "~> 0.7"},
      {:masu, "~> 0.8"},
      {:sake, "~> 0.4.4"},
      {:koyomi, "~> 0.2.1"},
      {:fude, "~> 0.8"},
      {:jumon, "~> 0.2"},
      {:storehouse, "~> 0.3"},
      {:chime, "~> 0.1.0-dev"},
      {:oban, "~> 2.20"},
      {:cardbox, "~> 0.2"},
      {:sekisho, "~> 0.1.1"},
      {:narabe, "~> 0.2"},
      {:tz, "~> 0.28"},
      # 0.43 frees a statement without waiting for its connection's lock,
      # which another connection could hold through SQLite's busy timeout:
      # two writers at once (a change and its notifications) stalled each
      # other, and one failed with "database is locked".
      {:exqlite, "~> 0.43"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": [
        "compile",
        "esbuild kotoba_extensions",
        "tailwind notebook",
        "esbuild notebook"
      ],
      "assets.deploy": [
        "tailwind notebook --minify",
        "esbuild kotoba_extensions --minify",
        "esbuild notebook --minify",
        "phx.digest"
      ],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
