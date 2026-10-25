defmodule Notebook.Spaces.Folder do
  @moduledoc """
  A folder of a space's pages. Folders are shallow on purpose: a folder
  at the top of a space may hold folders, and those hold only pages. What
  wants to go deeper is a link, or a collection.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "folders" do
    field :name, :string
    # Its place among its siblings, folders and pages alike (Narabe).
    field :position, :string
    # Published (Notebook.Publishing): its public path's last word, since
    # when, and by whom.
    field :slug, :string
    field :published_at, :utc_datetime
    belongs_to :published_by, Notebook.Accounts.User
    belongs_to :space, Notebook.Spaces.Space
    belongs_to :parent, __MODULE__
    has_many :children, __MODULE__, foreign_key: :parent_id
    has_many :pages, Notebook.Pages.Page
    timestamps(type: :utc_datetime)
  end

  def changeset(folder, attrs) do
    folder
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> update_change(:name, &String.trim/1)
    |> validate_length(:name, min: 1, max: 80)
  end
end
