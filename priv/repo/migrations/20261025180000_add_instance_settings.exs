defmodule Notebook.Repo.Migrations.AddInstanceSettings do
  use Ecto.Migration

  # The notebook's own settings, kept by its admins: where its files are
  # (Notebook.Storage), and what comes after. An admin is who set the
  # notebook up: its first person, at once.
  def change do
    alter table(:users) do
      add :admin, :boolean, null: false, default: false
    end

    execute "UPDATE users SET admin = 1 WHERE id = (SELECT min(id) FROM users)", ""

    create table(:settings, primary_key: false) do
      add :key, :string, primary_key: true
      add :value, :map, null: false, default: %{}
      timestamps(type: :utc_datetime)
    end
  end
end
