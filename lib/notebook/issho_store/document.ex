defmodule Notebook.IsshoStore.Document do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  schema "issho_documents" do
    field :epoch, :string
    field :revision, :integer
    field :document, :map
    field :content, :map
  end
end
