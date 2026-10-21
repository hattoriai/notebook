defmodule Notebook.Repo.Migrations.AddKindsToPages do
  use Ecto.Migration

  # A page is a text (Kotoba), a board (Hakushi) or a table (Masu). A board
  # keeps its graph; a table's rows are rows of their own.
  def change do
    alter table(:pages) do
      add :kind, :string, null: false, default: "text"
      add :board, :map
    end

    create table(:page_rows) do
      add :page_id, references(:pages, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :status, :string, null: false, default: "todo"
      add :owner, :string
      add :due_on, :date
      add :points, :integer
      timestamps(type: :utc_datetime)
    end

    create index(:page_rows, [:page_id])
  end
end
