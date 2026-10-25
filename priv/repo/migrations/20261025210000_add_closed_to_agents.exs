defmodule Notebook.Repo.Migrations.AddClosedToAgents do
  use Ecto.Migration

  # Pages and spaces off limits to agents: people still work there, agents
  # may not read them, list them, find them or join their rooms.
  def change do
    alter table(:pages) do
      add :closed_to_agents, :boolean, null: false, default: false
    end

    alter table(:spaces) do
      add :closed_to_agents, :boolean, null: false, default: false
    end
  end
end
