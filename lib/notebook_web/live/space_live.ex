defmodule NotebookWeb.SpaceLive do
  @moduledoc """
  A space: its folders and pages, a folder of it, its members, and the
  form that makes a team space. What a person sees and may do is their
  role in the space (`Notebook.Permissions`): editors make pages and
  folders, admins rename the space and manage its members.
  """
  use NotebookWeb, :live_view

  alias Notebook.{Accounts, Spaces}
  alias Notebook.Spaces.{Member, Space}
  alias NotebookWeb.Sidebar

  @impl true
  def mount(params, _session, socket) do
    {:ok, socket |> assign(folder_form: nil, renaming: false) |> load(params)}
  end

  # The tree is the sidebar's, loaded again when anything in it changes,
  # so the folders and pages on screen are its part for the space.
  defp with_node(%{live_action: action} = assigns) when action in [:show, :folder] do
    node = Enum.find(assigns.tree, &(&1.space.id == assigns.space.id))
    assign(assigns, :node, folder_node(node, assigns.folder))
  end

  defp with_node(assigns), do: assigns

  @impl true
  def handle_params(params, _url, socket) do
    if socket.assigns[:loaded] == params,
      do: {:noreply, socket},
      else: {:noreply, load(socket, params)}
  end

  defp load(%{assigns: %{live_action: :new}} = socket, _params) do
    assign(socket,
      page_title: "New space",
      space: nil,
      form: to_form(Spaces.change(%Space{}))
    )
  end

  defp load(socket, %{"id" => id} = params) do
    scope = socket.assigns.current_scope
    space = Spaces.get!(scope, id)
    folder = params["folder_id"] && Spaces.get_folder!(scope, params["folder_id"])

    if folder && folder.space_id != space.id, do: raise(Ecto.NoResultsError, queryable: Space)

    socket
    |> assign(
      loaded: params,
      space: space,
      folder: folder,
      parent: folder && folder.parent_id && Spaces.get_folder!(scope, folder.parent_id),
      can_edit?: Spaces.allowed?(scope, :edit, space),
      can_manage?: Spaces.allowed?(scope, :manage, space),
      members: Spaces.members(space),
      page_title: if(folder, do: folder.name, else: space.name),
      form: to_form(Spaces.change(space))
    )
    |> load_members()
  end

  # The part of the space's tree on screen: the space's top, or a folder.
  defp folder_node(node, nil), do: node || %{folders: [], pages: []}

  defp folder_node(node, folder) do
    find = fn nodes, find ->
      Enum.find_value(nodes, fn n ->
        if n.folder.id == folder.id, do: n, else: find.(n.folders, find)
      end)
    end

    (node && find.(node.folders, find)) || %{folder: folder, folders: [], pages: []}
  end

  defp load_members(%{assigns: %{live_action: :members, space: space}} = socket) do
    unless socket.assigns.can_manage?, do: raise(Ecto.NoResultsError, queryable: Space)

    assign(socket,
      outsiders: Spaces.outsiders(space),
      add_form: to_form(%{"user_id" => "", "role" => "editor"})
    )
  end

  defp load_members(socket), do: socket

  @impl true
  def render(assigns) do
    assigns = with_node(assigns)

    ~H"""
    <div class="notebook-shell notebook-with-sidebar">
      <.sidebar tree={@tree} current={current(assigns)} />
      <main class="notebook-main">
        <div class="flash-area"><Layouts.flash_group flash={@flash} /></div>

        <div :if={@live_action == :new} class="page-view">
          <div class="page-heading">
            <p class="eyebrow">A new space</p>
            <h1>Who is it for?</h1>
            <p>A space for a team, a project or a client: its people, its folders and its pages.</p>
          </div>
          <.form
            for={@form}
            id="space-form"
            phx-change="validate"
            phx-submit="create"
            class="page-form"
          >
            <label for="space_name" class="field-label">Name</label>
            <input
              id="space_name"
              type="text"
              name="space[name]"
              value={@form[:name].value}
              placeholder="The forge, Clients, Book club…"
              maxlength="60"
              required
              autofocus
            />
            <p :for={msg <- errors(@form[:name])} class="field-error">{msg}</p>
            <label for="space_description" class="field-label">What it is for</label>
            <input
              id="space_description"
              type="text"
              name="space[description]"
              value={@form[:description].value}
              placeholder="One line, for the people you add"
              maxlength="200"
            />
            <p class="field-hint">You are its admin. Add its people once it is made.</p>
            <button class="button button-primary" type="submit">Make the space</button>
          </.form>
        </div>

        <div :if={@live_action in [:show, :folder]} class="space-view">
          <div class="page-nav">
            <nav class="breadcrumb" aria-label="Where this is">
              <.link navigate={~p"/spaces/#{@space.id}"}>{@space.name}</.link>
              <span :if={@parent} aria-hidden="true">/</span>
              <.link :if={@parent} navigate={~p"/spaces/#{@space.id}/folders/#{@parent.id}"}>
                {@parent.name}
              </.link>
            </nav>
            <div class="page-nav-end">
              <.link
                :if={@can_manage? and is_nil(@folder) and @space.kind == "team"}
                navigate={~p"/spaces/#{@space.id}/members"}
                class="command-link"
              >
                <.icon name="hero-users" class="size-4" /> Members
              </.link>
              <.command_button id="space-commands" class="command-link" />
            </div>
          </div>

          <div class="page-heading space-heading">
            <p class="eyebrow">
              <.icon
                name={if(@folder, do: "hero-folder", else: Sidebar.space_icon(@space))}
                class="size-3.5"
              />
              {heading_kicker(@space, @folder, @members)}
            </p>
            <h1 :if={not @renaming}>{if @folder, do: @folder.name, else: @space.name}</h1>
            <.form
              :if={@renaming}
              for={%{}}
              as={:rename}
              id="rename-form"
              phx-submit="rename"
              class="rename-form"
            >
              <input
                name="rename[name]"
                value={if @folder, do: @folder.name, else: @space.name}
                maxlength="80"
                autofocus
                required
              />
              <button class="button button-primary" type="submit">Save</button>
              <button class="copy-action" type="button" phx-click="cancel_rename">Cancel</button>
            </.form>
            <p :if={is_nil(@folder) and @space.description}>{@space.description}</p>
          </div>

          <div class="space-actions">
            <.link
              :if={@can_edit?}
              class="button button-primary"
              navigate={~p"/pages/new?#{new_page_params(@space, @folder)}"}
            >
              New page <span aria-hidden="true">↗</span>
            </.link>
            <button
              :if={@can_edit? and (is_nil(@folder) or is_nil(@folder.parent_id))}
              type="button"
              class="copy-action"
              phx-click="new_folder"
            >
              <.icon name="hero-folder-plus" class="size-4" /> New folder
            </button>
            <button
              :if={rename_allowed?(assigns)}
              type="button"
              class="copy-action"
              phx-click="start_rename"
            >
              <.icon name="hero-pencil" class="size-4" /> Rename
            </button>
            <button
              :if={@folder && @can_edit?}
              type="button"
              class="copy-action"
              phx-click="delete_folder"
              data-confirm="Delete this folder? Its pages move to the top of the space."
            >
              <.icon name="hero-trash" class="size-4" /> Delete folder
            </button>
          </div>

          <.form
            :if={@folder_form}
            for={@folder_form}
            id="folder-form"
            phx-submit="create_folder"
            class="folder-form"
          >
            <input
              name="folder[name]"
              placeholder={
                if @folder, do: "A folder in #{@folder.name}", else: "A folder in #{@space.name}"
              }
              maxlength="80"
              required
              autofocus
            />
            <button class="button button-primary" type="submit">Make folder</button>
            <button class="copy-action" type="button" phx-click="cancel_folder">Cancel</button>
          </.form>

          <div :if={@node.folders != []} class="folder-grid">
            <.link
              :for={child <- @node.folders}
              class="folder-card"
              navigate={~p"/spaces/#{@space.id}/folders/#{child.folder.id}"}
            >
              <.icon name="hero-folder" class="size-5" />
              <strong>{child.folder.name}</strong>
              <small>{count(child)}</small>
            </.link>
          </div>

          <div class="page-list">
            <div :if={@node.pages == [] and @node.folders == []} class="empty-state">
              <span class="empty-mark">✳</span>
              <h2>Nothing here yet.</h2>
              <p :if={@can_edit?}>Make a page, or a folder to keep pages together.</p>
              <p :if={not @can_edit?}>The space's editors have not made a page here.</p>
            </div>
            <.link :for={page <- @node.pages} class="page-row" navigate={~p"/pages/#{page.id}"}>
              <div>
                <span class="page-kicker">
                  <.icon name={Sidebar.page_icon(page.kind)} class="size-3.5" /> {kind_name(page.kind)}
                </span>
                <h2>{page.title}</h2>
              </div>
              <div class="page-meta">
                <time>{Calendar.strftime(page.updated_at, "%d %b %Y")}</time><span aria-hidden="true">↗</span>
              </div>
            </.link>
          </div>
        </div>

        <div :if={@live_action == :members} class="space-view">
          <div class="page-nav">
            <nav class="breadcrumb" aria-label="Where this is">
              <.link navigate={~p"/spaces/#{@space.id}"}>{@space.name}</.link>
              <span aria-hidden="true">/</span>
              <span>Members</span>
            </nav>
          </div>
          <div class="page-heading">
            <p class="eyebrow">Who is in {@space.name}</p>
            <h1>Members</h1>
            <p>
              A viewer reads, a commenter also comments, an editor also writes, an admin also manages the space. Their agents may do what they may.
            </p>
          </div>

          <.form
            :if={@outsiders != []}
            for={@add_form}
            id="add-member"
            phx-submit="add_member"
            class="member-add"
          >
            <select name="user_id" aria-label="Person">
              <option :for={user <- @outsiders} value={user.id}>{user.name}</option>
            </select>
            <select name="role" aria-label="Role">
              <option :for={role <- Member.roles()} value={role} selected={role == "editor"}>
                {role_name(role)}
              </option>
            </select>
            <button class="button button-primary" type="submit">Add</button>
          </.form>

          <ul class="member-list">
            <li :for={member <- @members} id={"member-#{member.id}"}>
              <span class="account-avatar">{Layouts.initials(member.user.name)}</span>
              <span class="member-name">
                {member.user.name}<small>{member.user.email}</small>
              </span>
              <form id={"member-role-#{member.id}"} phx-change="set_role" class="member-role">
                <input type="hidden" name="member_id" value={member.id} />
                <select name="role" aria-label={"Role of #{member.user.name}"}>
                  <option :for={role <- Member.roles()} value={role} selected={role == member.role}>
                    {role_name(role)}
                  </option>
                </select>
              </form>
              <button
                type="button"
                class="copy-action"
                phx-click="remove_member"
                phx-value-id={member.id}
                data-confirm={"Take #{member.user.name} out of #{@space.name}?"}
              >
                Remove
              </button>
            </li>
          </ul>
        </div>
      </main>
      <.command_palette
        jumon={@jumon}
        placeholder="Search pages, or type a command…"
        icons={~w(hero-document-text hero-pencil-square)}
      >
        <:icon :let={name}><.icon name={name} class="size-4" /></:icon>
      </.command_palette>
    </div>
    """
  end

  defp current(%{live_action: action, folder: %{id: id}}) when action == :folder,
    do: {:folder, id}

  defp current(%{space: %Space{id: id}}), do: {:space, id}
  defp current(_assigns), do: nil

  defp heading_kicker(_space, %{} = _folder, _members), do: "Folder"

  defp heading_kicker(%Space{kind: "general"}, nil, members),
    do: "Everyone · #{head_count(length(members))}"

  defp heading_kicker(%Space{kind: "private"}, nil, _members), do: "Only you, and your agent"
  defp heading_kicker(%Space{}, nil, members), do: "Team space · #{head_count(length(members))}"

  defp head_count(1), do: "1 person"
  defp head_count(n), do: "#{n} people"

  defp count(%{folders: folders, pages: pages}) do
    case {length(folders), length(pages)} do
      {0, 1} ->
        "1 page"

      {0, n} ->
        "#{n} pages"

      {f, n} ->
        "#{f} #{if f == 1, do: "folder", else: "folders"} · #{n} #{if n == 1, do: "page", else: "pages"}"
    end
  end

  defp new_page_params(space, nil), do: [space: space.id]
  defp new_page_params(space, folder), do: [space: space.id, folder: folder.id]

  defp rename_allowed?(%{folder: %{}} = assigns), do: assigns.can_edit?
  defp rename_allowed?(%{space: %Space{kind: "team"}} = assigns), do: assigns.can_manage?
  defp rename_allowed?(_assigns), do: false

  defp kind_name("board"), do: "BOARD"
  defp kind_name("table"), do: "TABLE"
  defp kind_name(_text), do: "PAGE"

  defp role_name(role), do: String.capitalize(role)

  defp errors(field) do
    if Phoenix.Component.used_input?(field),
      do: Enum.map(field.errors, &NotebookWeb.CoreComponents.translate_error/1),
      else: []
  end

  @impl true
  def handle_event("validate", %{"space" => params}, socket),
    do:
      {:noreply,
       assign(socket, form: to_form(Spaces.change(%Space{}, params), action: :validate))}

  def handle_event("create", %{"space" => params}, socket) do
    case Spaces.create_team(socket.assigns.current_scope, params) do
      {:ok, space} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{space.name} is made. Add its people.")
         |> push_navigate(to: ~p"/spaces/#{space.id}/members")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("new_folder", _params, socket),
    do: {:noreply, assign(socket, folder_form: to_form(%{"name" => ""}, as: :folder))}

  def handle_event("cancel_folder", _params, socket),
    do: {:noreply, assign(socket, folder_form: nil)}

  def handle_event("create_folder", %{"folder" => params}, socket) do
    %{current_scope: scope, space: space, folder: parent} = socket.assigns

    case Spaces.create_folder(scope, space, params, parent) do
      {:ok, folder} ->
        {:noreply,
         socket
         |> assign(folder_form: nil)
         |> push_navigate(to: ~p"/spaces/#{space.id}/folders/#{folder.id}")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not make that folder.")}
    end
  end

  def handle_event("start_rename", _params, socket),
    do: {:noreply, assign(socket, renaming: true)}

  def handle_event("cancel_rename", _params, socket),
    do: {:noreply, assign(socket, renaming: false)}

  def handle_event("rename", %{"rename" => %{"name" => name}}, socket) do
    %{current_scope: scope, space: space, folder: folder} = socket.assigns

    result =
      if folder,
        do: Spaces.rename_folder(scope, folder, %{name: name}),
        else: Spaces.update(scope, space, %{name: name})

    case result do
      {:ok, _} ->
        {:noreply, socket |> assign(renaming: false) |> Sidebar.assign_tree() |> reload()}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not rename it.")}
    end
  end

  def handle_event("delete_folder", _params, socket) do
    %{current_scope: scope, space: space, folder: folder} = socket.assigns
    {:ok, _} = Spaces.delete_folder(scope, folder)

    {:noreply,
     socket
     |> put_flash(:info, "#{folder.name} is deleted; its pages are at the top of #{space.name}.")
     |> push_navigate(to: ~p"/spaces/#{space.id}")}
  end

  def handle_event("add_member", %{"user_id" => user_id, "role" => role}, socket) do
    %{current_scope: scope, space: space} = socket.assigns
    user = Accounts.get_user!(user_id)

    case Spaces.add_member(scope, space, user, role) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "#{user.name} is in #{space.name}.") |> reload()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not add #{user.name}.")}
    end
  end

  def handle_event("set_role", %{"member_id" => id, "role" => role}, socket) do
    member = Enum.find(socket.assigns.members, &(to_string(&1.id) == id))

    case Spaces.set_role(socket.assigns.current_scope, member, role) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{member.user.name} is now #{role_article(role)}.")
         |> reload()}

      {:error, :last_admin} ->
        {:noreply, socket |> put_flash(:error, "A space keeps at least one admin.") |> reload()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not change that role.")}
    end
  end

  def handle_event("remove_member", %{"id" => id}, socket) do
    member = Enum.find(socket.assigns.members, &(to_string(&1.id) == id))
    me? = member.user_id == socket.assigns.current_scope.user.id

    case Spaces.remove_member(socket.assigns.current_scope, member) do
      {:ok, _} when me? ->
        {:noreply,
         socket
         |> put_flash(:info, "You left #{socket.assigns.space.name}.")
         |> push_navigate(to: ~p"/")}

      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{member.user.name} is out of #{socket.assigns.space.name}.")
         |> reload()}

      {:error, :last_admin} ->
        {:noreply, put_flash(socket, :error, "A space keeps at least one admin.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not remove #{member.user.name}.")}
    end
  end

  defp role_article("admin"), do: "an admin"
  defp role_article("editor"), do: "an editor"
  defp role_article(role), do: "a #{role}"

  defp reload(socket) do
    params =
      %{"id" => to_string(socket.assigns.space.id)}
      |> then(fn p ->
        if f = socket.assigns.folder, do: Map.put(p, "folder_id", to_string(f.id)), else: p
      end)

    load(socket, params)
  end
end
