defmodule Notebook.Repo.Migrations.AddUserIdentities do
  use Ecto.Migration

  def change do
    create table(:user_identities) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :uid, :string, null: false
      add :issuer, :string, null: false
      add :email, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_identities, [:provider, :issuer, :uid])
    create index(:user_identities, [:user_id])
    create index(:user_identities, [:email])
  end
end
