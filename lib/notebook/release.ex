defmodule Notebook.Release do
  @moduledoc """
  The release's database tasks, run without Mix: `bin/migrate` before the
  notebook starts (the Dockerfile's command), or by hand:

      bin/notebook eval "Notebook.Release.migrate()"
  """
  @app :notebook

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
