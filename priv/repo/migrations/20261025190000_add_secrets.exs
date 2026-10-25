defmodule Notebook.Repo.Migrations.AddSecrets do
  use Ecto.Migration

  # The notebook's secrets, encrypted by Notebook.Vault (Cloak).
  def change do
    create table(:secrets, primary_key: false) do
      add :name, :string, primary_key: true
      add :value, :binary, null: false
      timestamps(type: :utc_datetime)
    end
  end
end
