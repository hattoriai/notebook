defmodule Notebook.CollabStore.Draft do
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  schema "collab_drafts" do
    field :epoch, :string
    field :revision, :integer
    field :state, :map
    field :content, Kotoba.Content
  end
end
