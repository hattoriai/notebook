defmodule Notebook.Repo.Migrations.AddInvitations do
  use Ecto.Migration

  # The links an admin makes for people to join an invite-only notebook
  # (Notebook.Invitations): each one is used once, before it expires. Only
  # the token's hash is kept.
  def change do
    create table(:invitations) do
      add :token_hash, :binary, null: false
      add :invited_by_id, references(:users, on_delete: :nilify_all)
      add :used_by_id, references(:users, on_delete: :nilify_all)
      add :used_at, :utc_datetime
      add :expires_at, :utc_datetime, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:invitations, [:token_hash])
  end
end
