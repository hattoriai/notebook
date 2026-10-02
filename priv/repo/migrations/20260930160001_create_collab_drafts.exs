defmodule Notebook.Repo.Migrations.CreateCollabDrafts do
  use Ecto.Migration

  # The shared editor's accepted revision of each page, keyed by the page id.
  def change do
    create table(:collab_drafts, primary_key: false) do
      add :id, :string, primary_key: true
      add :epoch, :string, null: false
      add :revision, :integer, null: false
      add :state, :map, null: false
      add :content, :map, null: false
    end
  end
end
