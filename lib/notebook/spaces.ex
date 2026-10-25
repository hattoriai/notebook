defmodule Notebook.Spaces do
  @moduledoc """
  The notebook's spaces and their folders. One deployment is one
  organisation: every account is in General, each person has a Private
  space that is theirs alone, and people make team spaces and add
  members to them. What a member may do is their role in the space
  (`Notebook.Permissions`).
  """
  import Ecto.Query

  alias Notebook.Accounts.{Scope, User}
  alias Notebook.Pages.Page
  alias Notebook.Permissions
  alias Notebook.Repo
  alias Notebook.Spaces.{Folder, Member, Space}

  @tree "notebook:tree"

  @doc "Subscribes the caller to `:tree_changed`, sent when a space, a folder or a page is made, renamed, moved or archived."
  def subscribe_tree, do: Phoenix.PubSub.subscribe(Notebook.PubSub, @tree)

  @doc "Tells the tree's subscribers (the sidebars) that it changed."
  def tree_changed, do: Phoenix.PubSub.broadcast(Notebook.PubSub, @tree, :tree_changed)

  # The result of a change, after telling the tree's subscribers.
  defp changed({:ok, _} = result), do: tap(result, fn _ -> tree_changed() end)
  defp changed(result), do: result

  ## Spaces

  @doc "The spaces the scope may read: General, their Private space, then their teams by name."
  def list(scope) do
    Space
    |> Permissions.where_allowed(scope, :read)
    |> order_by([s],
      asc: fragment("CASE ? WHEN 'general' THEN 0 WHEN 'private' THEN 1 ELSE 2 END", s.kind),
      asc: s.name
    )
    |> Repo.all()
  end

  @doc "A space the scope may read, or raises (a 404)."
  def get!(scope, id) do
    space = Repo.get!(Space, id)
    Permissions.authorize!(scope, :read, space)
    space
  end

  @doc "The space everyone is in."
  def general!, do: Repo.get_by!(Space, kind: "general")

  @doc "A person's Private space."
  def private!(%User{id: id}), do: Repo.get_by!(Space, kind: "private", owner_id: id)

  @doc """
  Makes a new account at home: a member of General (an editor), with a
  Private space of its own. Run it again and nothing changes.
  """
  def welcome(%User{} = user) do
    Repo.transact(fn ->
      general =
        Repo.get_by(Space, kind: "general") ||
          Repo.insert!(%Space{
            name: "General",
            kind: "general",
            description: "Everyone in the notebook."
          })

      join!(general, user, "editor")

      private =
        Repo.get_by(Space, kind: "private", owner_id: user.id) ||
          Repo.insert!(%Space{name: "Private", kind: "private", owner_id: user.id})

      join!(private, user, "admin")
      Permissions.changed()
      {:ok, user}
    end)
  end

  defp join!(space, user, role) do
    Repo.insert!(%Member{space_id: space.id, user_id: user.id, role: role},
      on_conflict: :nothing,
      conflict_target: [:space_id, :user_id]
    )
  end

  @doc "Makes a team space, with the scope's person as its admin."
  def create_team(%Scope{user: user}, attrs) do
    Repo.transact(fn ->
      with {:ok, space} <- %Space{kind: "team"} |> Space.changeset(attrs) |> Repo.insert() do
        join!(space, user, "admin")
        Permissions.changed()
        {:ok, space}
      end
    end)
    |> changed()
  end

  @doc "Renames a team space, or changes its description: its admins may."
  def update(scope, %Space{kind: "team"} = space, attrs) do
    with :ok <- Permissions.authorize(scope, :manage, space) do
      space |> Space.changeset(attrs) |> Repo.update() |> changed()
    end
  end

  def update(_scope, %Space{}, _attrs), do: {:error, :fixed}

  @doc """
  Closes a space to agents, with every page in it, or opens it again: its
  admins may, a Private space's person too.
  """
  def set_closed_to_agents(scope, %Space{} = space, closed?) when is_boolean(closed?) do
    with :ok <- Permissions.authorize(scope, :manage, space) do
      space |> Ecto.Changeset.change(closed_to_agents: closed?) |> Repo.update() |> changed()
    end
  end

  def change(space, attrs \\ %{}), do: Space.changeset(space, attrs)

  @doc "Whether the scope may do what the permission says in the space."
  def allowed?(scope, permission, space), do: Permissions.allowed?(scope, permission, space)

  ## Members

  @doc "A space's members and their roles, by name."
  def members(%Space{id: id}) do
    from(m in Member,
      join: u in assoc(m, :user),
      where: m.space_id == ^id,
      order_by: u.name,
      preload: [user: u]
    )
    |> Repo.all()
  end

  @doc "Adds a person to a team space with a role (its admins may), and tells them."
  def add_member(scope, %Space{kind: "team"} = space, %User{} = user, role) do
    with :ok <- Permissions.authorize(scope, :manage, space),
         {:ok, member} <-
           %Member{space_id: space.id, user_id: user.id}
           |> Member.changeset(%{role: role})
           |> Repo.insert() do
      Permissions.changed()
      Notebook.Notifications.added_to_space(space, user, role, scope.user)
      changed({:ok, member})
    end
  end

  def add_member(_scope, %Space{}, _user, _role), do: {:error, :fixed}

  @doc "Changes a member's role. A team space keeps at least one admin."
  def set_role(scope, %Member{} = member, role) do
    member = Repo.preload(member, :space)

    with :ok <- Permissions.authorize(scope, :manage, member.space),
         :ok <- team(member.space),
         :ok <- keeps_admin(member, role),
         {:ok, member} <- member |> Member.changeset(%{role: role}) |> Repo.update() do
      Permissions.changed()
      changed({:ok, member})
    end
  end

  @doc "Takes a person out of a team space. A team space keeps at least one admin."
  def remove_member(scope, %Member{} = member) do
    member = Repo.preload(member, :space)

    with :ok <- Permissions.authorize(scope, :manage, member.space),
         :ok <- team(member.space),
         :ok <- keeps_admin(member, nil),
         {:ok, member} <- Repo.delete(member) do
      Permissions.changed()
      changed({:ok, member})
    end
  end

  defp team(%Space{kind: "team"}), do: :ok
  defp team(%Space{}), do: {:error, :fixed}

  defp keeps_admin(%Member{role: "admin", space_id: space_id}, new_role)
       when new_role != "admin" do
    admins =
      Repo.aggregate(
        from(m in Member, where: m.space_id == ^space_id and m.role == "admin"),
        :count
      )

    if admins > 1, do: :ok, else: {:error, :last_admin}
  end

  defp keeps_admin(_member, _role), do: :ok

  @doc "The people who are not yet in a space, to add."
  def outsiders(%Space{id: id}) do
    from(u in User,
      where: u.id not in subquery(from m in Member, where: m.space_id == ^id, select: m.user_id),
      order_by: u.name
    )
    |> Repo.all()
  end

  ## Folders

  @doc """
  Makes a folder in a space (its editors may), at its top, or in a folder
  at its top: two levels at most.
  """
  def create_folder(scope, %Space{} = space, attrs, parent \\ nil) do
    with :ok <- Permissions.authorize(scope, :edit, space),
         :ok <- parent_ok(parent, space) do
      %Folder{space_id: space.id, parent_id: parent && parent.id}
      |> Folder.changeset(attrs)
      |> Narabe.Ecto.Mixed.put_position(Repo, order(space))
      |> Repo.insert()
      |> changed()
    end
  end

  defp parent_ok(nil, _space), do: :ok
  defp parent_ok(%Folder{space_id: id, parent_id: nil}, %Space{id: id}), do: :ok
  defp parent_ok(%Folder{space_id: id}, %Space{id: id}), do: {:error, :too_deep}
  defp parent_ok(%Folder{}, %Space{}), do: {:error, :other_space}

  @doc "A folder the scope may read, or raises (a 404)."
  def get_folder!(scope, id) do
    folder = Repo.get!(Folder, id)
    Permissions.authorize!(scope, :read, folder)
    folder
  end

  def rename_folder(scope, %Folder{} = folder, attrs) do
    with :ok <- Permissions.authorize(scope, :edit, folder) do
      folder |> Folder.changeset(attrs) |> Repo.update() |> changed()
    end
  end

  @doc "Deletes a folder and the folders in it; their pages go to the top of the space."
  def delete_folder(scope, %Folder{} = folder) do
    with :ok <- Permissions.authorize(scope, :edit, folder) do
      Repo.transact(fn ->
        ids = [
          folder.id | Repo.all(from f in Folder, where: f.parent_id == ^folder.id, select: f.id)
        ]

        Repo.update_all(from(p in Page, where: p.folder_id in ^ids), set: [folder_id: nil])
        Repo.delete(folder)
      end)
      |> changed()
    end
  end

  def change_folder(folder, attrs \\ %{}), do: Folder.changeset(folder, attrs)

  ## The sidebar

  @doc """
  A space's folders and pages as one ordered tree (`Narabe.Ecto.Mixed`):
  its folders (two levels deep at most) and its pages that are not
  archived, each sibling list in the order people put it in.
  """
  def order(%Space{id: id}) do
    Narabe.Ecto.Mixed.new(
      [
        folder: [from: where(Folder, space_id: ^id), parent: :parent_id],
        page: [
          from: where(Page, [p], p.space_id == ^id and is_nil(p.archived_at)),
          parent: :folder_id
        ]
      ],
      parents: :folder,
      rules: [max_depth: 3]
    )
  end

  @doc """
  Moves pages and folders within a space's tree, as its sidebar sends it
  (`Narabe.Move`, ids such as `"page:9"`): the space's editors may. A
  folder in a folder holds only pages, so a folder goes at most one level
  down, and a folder that holds folders stays at the top.
  """
  def move(scope, %Space{} = space, %Narabe.Move{} = move) do
    tree = order(space)

    with :ok <- Permissions.authorize(scope, :edit, space),
         :ok <- shallow(tree, move) do
      tree_result = Narabe.Ecto.Mixed.move(Repo, tree, move)
      changed(tree_result)
    end
  end

  # Moved folders end at most two levels deep, their own folders counted.
  defp shallow(tree, %Narabe.Move{ids: ids, parent: parent}) do
    folders =
      for id <- ids,
          {:ok, {"folder", pk}} <- [Narabe.Ecto.Mixed.parse_id(tree, to_string(id))],
          do: pk

    parent_depth =
      case parent && Narabe.Ecto.Mixed.parse_id(tree, to_string(parent)) do
        {:ok, {"folder", pk}} -> if Repo.get!(Folder, pk).parent_id, do: 2, else: 1
        _top -> 0
      end

    holds_folders? = Repo.exists?(from f in Folder, where: f.parent_id in ^folders)
    height = if holds_folders?, do: 2, else: 1

    if folders == [] or parent_depth + height <= 2, do: :ok, else: {:error, :too_deep}
  end

  @doc """
  The spaces the scope may read, each with its tree: the items the
  sidebar's `<.tree>` draws (`Narabe.Ecto.Mixed.items/2`), the same as
  folders (and theirs) and pages, whether the scope may move them, and
  its order.

      [%{space: %Space{}, items: [...], folders: [%{folder: %Folder{}, folders: [...], pages: [...]}], pages: [...], can_edit?: true, order: %Narabe.Ecto.Mixed{}}]
  """
  def tree(scope) do
    for space <- list(scope) do
      order = order(space)
      items = Narabe.Ecto.Mixed.items(Repo, order)
      children = Enum.group_by(items, & &1.parent_id)

      node = fn parent, node ->
        kids = Map.get(children, parent, [])

        %{
          folders:
            for %{kind: "folder"} = item <- kids do
              Map.put(node.(item.id, node), :folder, item.record)
            end,
          pages: for(%{kind: "page", record: page} <- kids, do: page)
        }
      end

      space
      |> then(&%{space: &1, items: items, order: order, can_edit?: allowed?(scope, :edit, &1)})
      |> Map.merge(node.(nil, node))
    end
  end
end
