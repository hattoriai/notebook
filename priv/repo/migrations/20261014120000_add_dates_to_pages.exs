defmodule Notebook.Repo.Migrations.AddDatesToPages do
  use Ecto.Migration

  # SQLite has no range type: the days a page covers are an ISO 8601
  # interval in a text column (Koyomi.DateRange, storage: :string), and
  # the revisit rule is its RFC 5545 text (Koyomi.Recurrence).
  def change do
    alter table(:pages) do
      add :due_on, :date
      add :covers, :string
      add :review_at, :utc_datetime
      add :revisit, :string
    end

    create index(:pages, [:due_on])
    create index(:pages, [:review_at])
  end
end
