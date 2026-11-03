defmodule Notebook.Repo.Migrations.AddIconAndArchivedAtToSpaces do
  use Ecto.Migration

  # A space's icon (one of the notebook's, an emoji, or an image), and when
  # it went to the Archive, with its pages.
  def change do
    alter table(:spaces) do
      add :icon, :string
      add :archived_at, :utc_datetime
    end
  end
end
