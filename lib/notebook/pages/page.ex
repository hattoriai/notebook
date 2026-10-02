defmodule Notebook.Pages.Page do
  use Ecto.Schema
  import Ecto.Changeset

  schema "pages" do
    field :title, :string
    field :body, Kotoba.Content
    belongs_to :author, Notebook.Accounts.User
    timestamps(type: :utc_datetime)
  end

  def changeset(page, attrs) do
    page
    |> cast(attrs, [:title, :body])
    |> validate_required([:title])
    |> validate_length(:title, max: 160)
  end
end
