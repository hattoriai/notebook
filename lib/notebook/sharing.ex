defmodule Notebook.Sharing do
  @moduledoc """
  Pages and folders shared beyond their space (Sekisho's grants): with a
  person, as a viewer, a commenter or an editor, or with anyone who has
  the link (a page to read or to comment on, a folder to read). A folder
  shares its pages, and the folders in it. A page's or a folder's editors
  share it, and no one gives more than they have.

  A link's token is shown once, when it is made (the grants keep its
  hash): whoever follows the link keeps it in their session, and their
  scope carries it (`Notebook.Accounts.Scope.with_links/2`). Making a new
  link takes back the last one.
  """
  import Ecto.Query

  alias Notebook.Accounts.{Scope, User}
  alias Notebook.Pages.Page
  alias Notebook.Spaces.Folder
  alias Notebook.{Permissions, Repo, Spaces}

  @roles ~w(viewer commenter editor)

  @doc "The roles a page or a folder is shared with a person as."
  def roles, do: @roles

  @doc "The roles a link gives: a page's, to read or to comment; a folder's, to read."
  def link_roles(%Page{}), do: ~w(viewer commenter)
  def link_roles(%Folder{}), do: ~w(viewer)

  @doc "Whether the scope may share it: its editors may."
  def can_share?(scope, resource), do: Permissions.allowed?(scope, :edit, resource)

  @doc """
  Who it is shared with, beyond its space: each person with their role,
  by name, and the link's role (or nil). The scope may share it.
  """
  def access(scope, resource) do
    with {:ok, grants} <- Permissions.grants(scope, resource) do
      users =
        grants
        |> Enum.filter(&(&1.actor_type == "users"))
        |> Enum.map(& &1.actor_id)
        |> then(&Repo.all(from u in User, where: u.id in ^&1))
        |> Map.new(&{&1.id, &1})

      people =
        for %{actor_type: "users", actor_id: id, role: role} <- grants,
            user = users[id],
            do: %{user: user, role: role}

      link = Enum.find_value(grants, fn g -> g.actor_type == "link" && g.role end)
      {:ok, %{people: Enum.sort_by(people, & &1.user.name), link: link}}
    end
  end

  @doc """
  Shares it with a person, as a role (their last role on it goes), and
  tells them: the scope may share it, up to their own role.
  """
  def share(%Scope{} = scope, resource, %User{} = user, role) when role in @roles do
    with {:ok, %{people: people}} <- access(scope, resource),
         previous = Enum.find_value(people, &(&1.user.id == user.id && &1.role)),
         {:ok, grant} <-
           Permissions.grant(scope, user, String.to_existing_atom(role), on: resource) do
      if previous && previous != role do
        {:ok, _} =
          Permissions.revoke(scope, user, String.to_existing_atom(previous), on: resource)
      end

      if is_nil(previous), do: Notebook.Notifications.shared(resource, user, role, scope.user)
      Spaces.tree_changed()
      {:ok, grant}
    end
  end

  @doc "Takes it back from a person: the scope may share it."
  def unshare(%Scope{} = scope, resource, %User{} = user) do
    with {:ok, %{people: people}} <- access(scope, resource) do
      for %{user: %{id: id}, role: role} <- people, id == user.id do
        {:ok, _} = Permissions.revoke(scope, user, String.to_existing_atom(role), on: resource)
      end

      Spaces.tree_changed()
      :ok
    end
  end

  @doc """
  Shares it with anyone who has the link, as a role, in place of the last
  link: gives the link's token, shown once.
  """
  def link(%Scope{} = scope, resource, role) do
    with true <- role in link_roles(resource) || {:error, :role},
         :ok <- unlink(scope, resource),
         {:ok, %{token: token}} <-
           Permissions.grant(scope, :link, String.to_existing_atom(role), on: resource) do
      {:ok, token}
    end
  end

  @doc "Takes back the link: who follows it no more opens it."
  def unlink(%Scope{} = scope, resource) do
    with {:ok, %{link: link}} <- access(scope, resource) do
      if link,
        do:
          {:ok, _} = Permissions.revoke(scope, :link, String.to_existing_atom(link), on: resource)

      :ok
    end
  end

  @doc "The address of a link to it, with its token."
  def url(%Page{id: id}, token), do: NotebookWeb.Endpoint.url() <> "/pages/#{id}?key=#{token}"

  def url(%Folder{id: id, space_id: space_id}, token),
    do: NotebookWeb.Endpoint.url() <> "/spaces/#{space_id}/folders/#{id}?key=#{token}"

  @doc "The people it may be shared with: everyone but the scope's person and those it is shared with."
  def candidates(%Scope{user: me} = scope, resource) do
    shared =
      case access(scope, resource) do
        {:ok, %{people: people}} -> Enum.map(people, & &1.user.id)
        _ -> []
      end

    Repo.all(from u in User, where: u.id != ^me.id and u.id not in ^shared, order_by: u.name)
  end

  @doc """
  The pages shared with the scope's person outside their spaces (with
  them, in a folder shared with them, or by a link they followed), by
  title: the sidebar's "Shared with you".
  """
  def shared_with(%Scope{} = scope) do
    spaces = scope |> Spaces.list() |> Enum.map(& &1.id)

    Page
    |> Permissions.where_allowed(scope, :read)
    |> where([p], p.space_id not in ^spaces and is_nil(p.archived_at))
    |> order_by([p], asc: p.title)
    |> Repo.all()
  end
end
