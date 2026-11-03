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
    |> where([s], is_nil(s.archived_at))
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
      space
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.force_change(:closed_to_agents, closed?)
      |> Repo.update()
      |> changed()
    end
  end

  def change(space, attrs \\ %{}), do: Space.changeset(space, attrs)

  ## Icons

  @doc """
  The notebook's icons a space may have, besides an emoji or an image:
  `{name, label, keywords}`, as `NotebookWeb.Icons.named/1` draws them.
  """
  def icons do
    [
      {"hero-user-group", "Team", ~w(people group)},
      {"hero-building-office-2", "Office", ~w(company organisation)},
      {"hero-lock-closed", "Private", ~w(lock secret)},
      {"hero-briefcase", "Work", ~w(job business)},
      {"hero-rocket-launch", "Launch", ~w(project start)},
      {"hero-light-bulb", "Ideas", ~w(idea brainstorm)},
      {"hero-beaker", "Research", ~w(lab science)},
      {"hero-code-bracket", "Engineering", ~w(code dev)},
      {"hero-paint-brush", "Design", ~w(art brand)},
      {"hero-megaphone", "Marketing", ~w(announce)},
      {"hero-chart-bar", "Numbers", ~w(chart data finance)},
      {"hero-currency-dollar", "Money", ~w(finance sales)},
      {"hero-academic-cap", "Learning", ~w(school course)},
      {"hero-book-open", "Reading", ~w(book library)},
      {"hero-heart", "Care", ~w(love health)},
      {"hero-sparkles", "Magic", ~w(shiny new)},
      {"hero-fire", "Hot", ~w(fire urgent)},
      {"hero-globe-alt", "World", ~w(web global)},
      {"hero-home", "Home", ~w(house)},
      {"hero-camera", "Photos", ~w(photo media)},
      {"hero-musical-note", "Music", ~w(song audio)},
      {"hero-puzzle-piece", "Puzzle", ~w(game)},
      {"hero-wrench-screwdriver", "Tools", ~w(ops fix)},
      {"hero-calendar-days", "Plans", ~w(calendar schedule)},
      {"notebook-robot", "Agents", ~w(robot bot ai)}
    ]
  end

  @doc """
  Gives a space an icon: one of `icons/0`, an emoji, or nil for its kind's.
  Its admins may (General's are the notebook's admins).
  """
  def set_icon(scope, %Space{} = space, icon) do
    with :ok <- authorize_manage(scope, space),
         {:ok, updated} <-
           space |> Space.icon_changeset(blank(icon), icon_names()) |> Repo.update() do
      discard_image(space.icon, updated.icon)
      changed({:ok, updated})
    end
  end

  @doc """
  Gives a space an image of its own as its icon, from an upload at `path`
  (Storehouse: only the bytes make an image an image).
  """
  def set_icon_image(scope, %Space{} = space, path, name) do
    with :ok <- authorize_manage(scope, space),
         {:ok, file} <- store_image(path, name) do
      case set_icon(scope, space, "image:" <> file.url) do
        {:ok, space} ->
          {:ok, space}

        error ->
          Notebook.Storage.adapter().delete(file.key)
          error
      end
    end
  end

  defp store_image(path, name) do
    case Storehouse.store(path,
           name: name,
           accept: ~w(image/png image/jpeg image/gif image/webp),
           max_bytes: 2_000_000
         ) do
      {:ok, file} -> {:ok, file}
      {:existing, file} -> {:ok, file}
      {:error, reason} -> {:error, {:image, reason}}
    end
  end

  defp icon_names, do: for({name, _label, _keywords} <- icons(), do: name)

  defp blank(""), do: nil
  defp blank(icon), do: icon

  # The image a space had, once it has another icon (or none).
  defp discard_image("image:" <> url = old, new) when old != new do
    with "/uploads/kotoba/" <> key <- url, do: Notebook.Storage.store_of(key).delete(key)
    :ok
  end

  defp discard_image(_old, _new), do: :ok

  ## The Archive

  @doc """
  Puts a team space in the Archive, with its folders and pages: they leave
  the sidebar, the lists, the search and the agents' reach, for everyone,
  until it is restored. Its admins may, and the notebook's.
  """
  def archive(scope, %Space{kind: "team"} = space) do
    with :ok <- authorize_manage(scope, space) do
      space
      |> Ecto.Changeset.change(archived_at: DateTime.utc_now(:second))
      |> Repo.update()
      |> archive_changed()
    end
  end

  def archive(_scope, %Space{}), do: {:error, :fixed}

  @doc "Brings an archived space back, with its folders and pages."
  def restore(scope, %Space{archived_at: %DateTime{}} = space) do
    with :ok <- authorize_manage(scope, space) do
      space |> Ecto.Changeset.change(archived_at: nil) |> Repo.update() |> archive_changed()
    end
  end

  @doc """
  Deletes an archived space for good: its folders, its pages and all that
  is theirs (comments, drafts, tables, records, charts, shares), and its
  image. It cannot be undone.
  """
  def delete(scope, %Space{archived_at: %DateTime{}} = space) do
    with :ok <- authorize_manage(scope, space) do
      page_ids = Repo.all(from p in Page, where: p.space_id == ^space.id, select: p.id)
      folder_ids = Repo.all(from f in Folder, where: f.space_id == ^space.id, select: f.id)

      Repo.transact(fn ->
        delete_documents(page_ids)

        Repo.delete_all(
          from c in "cardbox_collections",
            where: c.owner_type == "page" and c.owner_id in ^Enum.map(page_ids, &to_string/1)
        )

        Repo.delete_all(
          from g in "sekisho_grants",
            where:
              (g.resource_type == "pages" and g.resource_id in ^page_ids) or
                (g.resource_type == "folders" and g.resource_id in ^folder_ids) or
                (g.resource_type == "spaces" and g.resource_id == ^space.id)
        )

        Repo.delete(space)
      end)
      |> tap(fn
        {:ok, _} -> discard_image(space.icon, nil)
        _error -> :ok
      end)
      |> archive_changed()
    end
  end

  def delete(_scope, %Space{}), do: {:error, :not_archived}

  # A page's collaborative documents (its text's drafts, its comments, its
  # charts' rooms), by their ids: "page:<id>" and "page:<id>/…".
  defp delete_documents([]), do: :ok

  defp delete_documents(page_ids) do
    for table <- ~w(collab_drafts issho_documents), id <- page_ids do
      Repo.delete_all(
        from d in table, where: d.id == ^"page:#{id}" or like(d.id, ^"page:#{id}/%")
      )
    end

    :ok
  end

  @doc "The archived spaces the scope may restore or delete: their admins', or all for the notebook's."
  def archived(scope) do
    query = from s in Space, where: not is_nil(s.archived_at), order_by: [desc: s.archived_at]

    if Scope.admin?(scope),
      do: Repo.all(query),
      else: query |> Permissions.where_allowed(scope, :manage) |> Repo.all()
  end

  @doc "Whether the scope may archive, restore or delete the space: its admins, and the notebook's."
  def manage?(scope, %Space{} = space), do: authorize_manage(scope, space) == :ok

  defp authorize_manage(scope, space) do
    if Scope.admin?(scope), do: :ok, else: Permissions.authorize(scope, :manage, space)
  end

  defp archive_changed(result) do
    changed(result)
    |> tap(fn
      {:ok, _} -> Permissions.changed()
      _error -> :ok
    end)
  end

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
      # A bot's roles are given on the bots' page (Notebook.Bots).
      where:
        u.id not in subquery(from m in Member, where: m.space_id == ^id, select: m.user_id) and
          not u.bot,
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
