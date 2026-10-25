defmodule Notebook.Spaces.Member do
  @moduledoc "A person in a space, with their role there."
  use Ecto.Schema
  import Ecto.Changeset

  @roles ~w(viewer commenter editor admin)

  schema "space_members" do
    field :role, :string, default: "editor"
    belongs_to :space, Notebook.Spaces.Space
    belongs_to :user, Notebook.Accounts.User
    timestamps(type: :utc_datetime)
  end

  @doc "The roles, from the least to the most."
  def roles, do: @roles

  def changeset(member, attrs) do
    member
    |> cast(attrs, [:role])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint([:space_id, :user_id], message: "is already in this space")
  end
end
