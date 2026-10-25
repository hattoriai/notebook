defmodule Notebook.Repo.Migrations.AddAgents do
  use Ecto.Migration

  # Agents with their own identity (Notebook.Agents): each one a person
  # connected, with its name and its own token, which can expire and be
  # revoked; kept as a hash, never as the token.
  def change do
    create table(:agents) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :token_hash, :binary, null: false
      add :token_hint, :string, null: false
      add :expires_at, :utc_datetime
      add :last_seen_at, :utc_datetime
      add :revoked_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create index(:agents, [:user_id])
    create unique_index(:agents, [:token_hash])

    # The inboxes of the agents of before, one a person ("agent:<user id>"):
    # an agent's key is its own now ("agent:<agent id>"), and none takes over
    # an inbox that was another's.
    execute "DELETE FROM issho_documents WHERE id LIKE 'issho.inbox/agent:%'", ""
  end
end
