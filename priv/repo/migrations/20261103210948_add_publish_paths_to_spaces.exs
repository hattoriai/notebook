defmodule Notebook.Repo.Migrations.AddPublishPathsToSpaces do
  use Ecto.Migration

  # Where a space's published pages are read: under their publisher's
  # handle ("people"), or at the top of the site ("solo"); none, the
  # notebook's default.
  def change do
    alter table(:spaces) do
      add :publish_paths, :string
    end
  end
end
