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
    # Off limits to agents, with every page in it (Notebook.Permissions).
    field :closed_to_agents, :boolean, default: false
    # One of the notebook's icons ("hero-fire"), an emoji, or an image
    # ("image:<url>"), as NotebookWeb.Icons.named/1 draws it; nil for its kind's.
    field :icon, :string
    # In the Archive, with its pages: out of the sidebar, the lists and the
    # search, for everyone, until it is restored or deleted for good.
    field :archived_at, :utc_datetime
    # Its name in its published pages' addresses (/open-source/kotoba), for
    # General and the team spaces: one list of names with handles and
    # slugs (Notebook.Publishing).
    field :slug, :string
    # Where its published pages are read: nil under its slug, "solo" at the
    # top of the site (/kotoba). A Private space's are under its person's
    # handle, always.
    field :publish_paths, :string
    belongs_to :owner, Notebook.Accounts.User
    has_many :members, Notebook.Spaces.Member
    has_many :folders, Notebook.Spaces.Folder
    has_many :pages, Notebook.Pages.Page
    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds

  @doc """
  A space's icon: one of `icons` (the notebook's), an emoji, an uploaded
  image (`"image:<url>"`), or none.
  """
  def icon_changeset(space, icon, icons) do
    space
    |> change(icon: icon)
    |> validate_change(:icon, fn :icon, icon ->
      if icon_ok?(icon, icons), do: [], else: [icon: "is not an icon"]
    end)
  end

  defp icon_ok?("image:" <> url, _icons), do: String.starts_with?(url, ["/", "https://"])
  defp icon_ok?(icon, icons), do: icon in icons or emoji?(icon)

  # An emoji Erabi's picker has (in any skin tone).
  defp emoji?(icon), do: Erabi.Emoji.name(icon, "en") != nil

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
