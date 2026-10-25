defmodule Notebook.Spaces.Space do
  @moduledoc """
  Where pages live. Every account is in General; each person has a
  Private space of their own; a team space has the members its admins
  add. A member's role in the space (viewer, commenter, editor, admin)
  is what they may do with its folders and pages (`Notebook.Permissions`).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(general private team)

  schema "spaces" do
    field :name, :string
    field :kind, :string, default: "team"
    field :description, :string
    belongs_to :owner, Notebook.Accounts.User
    has_many :members, Notebook.Spaces.Member
    has_many :folders, Notebook.Spaces.Folder
    has_many :pages, Notebook.Pages.Page
    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds

  @doc "A team space's name and description; General and Private keep theirs."
  def changeset(space, attrs) do
    space
    |> cast(attrs, [:name, :description])
    |> validate_required([:name])
    |> update_change(:name, &String.trim/1)
    |> validate_length(:name, min: 1, max: 60)
    |> validate_length(:description, max: 200)
    |> validate_inclusion(:kind, @kinds)
  end
end
