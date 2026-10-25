defmodule Notebook.Repo.Migrations.CreateCharts do
  use Ecto.Migration

  # A chart in a text page (Fude): its spec, and the table page whose rows
  # it draws.
  def change do
    create table(:charts) do
      add :page_id, references(:pages, on_delete: :delete_all), null: false
      add :source_id, references(:pages, on_delete: :delete_all), null: false
      add :spec, :map, null: false
      timestamps(type: :utc_datetime)
    end

    create index(:charts, [:page_id])
    create index(:charts, [:source_id])
  end
end
