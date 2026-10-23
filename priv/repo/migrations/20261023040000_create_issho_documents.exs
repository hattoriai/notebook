defmodule Notebook.Repo.Migrations.CreateIsshoDocuments do
  use Ecto.Migration

  # Issho's own documents (each page's comments, the agents' inboxes,
  # shared state), keyed by their document id.
  def change do
    create table(:issho_documents, primary_key: false) do
      add :id, :string, primary_key: true
      add :epoch, :string, null: false
      add :revision, :integer, null: false
      add :document, :map, null: false
      add :content, :map, null: false
    end
  end
end
