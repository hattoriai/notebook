defmodule NotebookWeb.Sidebar do
  @moduledoc """
  The notebook's sidebar: Home, the spaces the person may read, each with
  its folders and pages, and the Archive. Each space is a Narabe tree
  (`Notebook.Spaces.order/1`): its editors drag a page or a folder, or move
  it from the keyboard (Space, the arrows, Space), within and across its
  folders, and the order stays as they leave it. Every LiveView of the notebook
  mounts it (`on_mount`): it loads the person's tree, and loads it again
  when someone makes, renames, moves or archives a page, a folder or a
  space (`Notebook.Spaces.subscribe_tree/0`), so that it is the same for
  everyone.
  """
  use NotebookWeb, :html

  import Phoenix.LiveView
  import Narabe.Components, only: [tree: 1]

  alias Notebook.Spaces

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket), do: Spaces.subscribe_tree()

    socket =
      socket
      |> assign_tree()
      |> attach_hook(:sidebar, :handle_info, fn
        :tree_changed, socket -> {:halt, assign_tree(socket)}
        _message, socket -> {:cont, socket}
      end)
      |> attach_hook(:sidebar_move, :handle_event, &handle_move/3)

    {:cont, socket}
  end

  # A move in a space's tree: the space's editors may; the browser puts the
  # items back on an error.
  defp handle_move("sidebar_move:" <> space_id, params, socket) do
    node = Enum.find(socket.assigns.tree, &(to_string(&1.space.id) == space_id))

    result =
      with %{space: space} <- node || {:error, :not_found},
           {:ok, move} <- Narabe.Move.parse(params) do
        Spaces.move(socket.assigns.current_scope, space, move)
      end

    {:halt, Narabe.Live.reply(result), assign_tree(socket)}
  end

  defp handle_move(_event, _params, socket), do: {:cont, socket}

  @doc "Loads the person's tree again, after a change this LiveView made."
  def assign_tree(socket), do: assign(socket, :tree, Spaces.tree(socket.assigns.current_scope))

  attr :tree, :list, required: true
  attr :chime, :any, default: nil, doc: "the person's notifications (`Chime.Live`), for the Inbox"

  attr :current, :any,
    default: nil,
    doc: "what is open: {:page, id}, {:space, id}, {:folder, id}, :home or :archive"

  def sidebar(assigns) do
    ~H"""
    <button
      type="button"
      class="sidebar-show"
      phx-click={JS.dispatch("notebook:toggle-sidebar")}
      aria-label="Show the sidebar"
      title="Show the sidebar (⌘\\)"
    >
      <.panel_icon />
    </button>
    <nav id="sidebar" class="sidebar" aria-label="Spaces">
      <button
        type="button"
        class="sidebar-hide"
        phx-click={JS.dispatch("notebook:toggle-sidebar")}
        aria-label="Hide the sidebar"
        title="Hide the sidebar (⌘\\)"
      >
        <.panel_icon />
      </button>
      <div class="sidebar-top">
        <.link navigate={~p"/"} class={["sidebar-link", @current == :home && "is-current"]}>
          <.icon name="hero-home" class="size-4" /> Home
        </.link>
        <.inbox :if={@chime} chime={@chime} />
        <.command_button id="sidebar-commands" class="sidebar-link sidebar-search" />
      </div>

      <section :for={%{space: space} = node <- @tree} class="sidebar-space">
        <div class="sidebar-space-head">
          <.link
            navigate={~p"/spaces/#{space.id}"}
            class={["sidebar-space-name", @current == {:space, space.id} && "is-current"]}
          >
            <.icon name={space_icon(space)} class="size-4" />{space.name}
          </.link>
          <.link
            navigate={~p"/pages/new?space=#{space.id}"}
            class="sidebar-add"
            aria-label={"New page in #{space.name}"}
            title="New page"
          >
            <.icon name="hero-plus" class="size-3.5" />
          </.link>
        </div>
        <.tree
          :if={node.items != []}
          id={"space-tree-#{space.id}"}
          class="sidebar-tree"
          items={node.items}
          item_kind={:kind}
          item_label={&label/1}
          rules={node.order.rules}
          expanded={for item <- node.items, item.kind == "folder", do: item.id}
          on_move={"sidebar_move:#{space.id}"}
          readonly={not node.can_edit?}
          handle
          label={space.name}
        >
          <:item :let={item}><.tree_item item={item} current={@current} /></:item>
        </.tree>
        <p :if={node.items == []} class="sidebar-empty">No pages yet</p>
      </section>

      <div class="sidebar-bottom">
        <.link navigate={~p"/spaces/new"} class="sidebar-link">
          <.icon name="hero-squares-plus" class="size-4" /> New space
        </.link>
        <.link navigate={~p"/archive"} class={["sidebar-link", @current == :archive && "is-current"]}>
          <.icon name="hero-archive-box" class="size-4" /> Archive
        </.link>
        <.link navigate={~p"/agents"} class={["sidebar-link", @current == :agents && "is-current"]}>
          <.icon name="hero-sparkles" class="size-4" /> Agents
        </.link>
      </div>
    </nav>
    """
  end

  attr :chime, :any, required: true

  # The person's notifications (Chime): a dot while some are unseen, the
  # number unread, and the feed beside the sidebar while it is open.
  defp inbox(assigns) do
    ~H"""
    <div class="sidebar-inbox">
      <button
        type="button"
        id="sidebar-inbox"
        class={["sidebar-link", @chime.open && "is-current"]}
        phx-click="chime:toggle"
        aria-expanded={to_string(@chime.open)}
      >
        <span class="sidebar-inbox-icon">
          <.icon name="hero-inbox" class="size-4" />
          <span :if={@chime.unseen > 0} class="chime-dot" aria-hidden="true"></span>
        </span>
        Inbox
        <span :if={@chime.unread > 0} class="sidebar-inbox-count" aria-label={"#{@chime.unread} unread"}>
          {@chime.unread}
        </span>
      </button>
      <Chime.Components.feed chime={@chime} title="Inbox" empty="Nothing new. Back to your pages." />
    </div>
    """
  end

  # A window with its left column, the sidebar, marked: the icon editors
  # give the button that hides and shows it. Heroicons' stroke and size.
  defp panel_icon(assigns) do
    ~H"""
    <svg
      class="size-[18px]"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.5"
      aria-hidden="true"
    >
      <rect x="3" y="4.5" width="18" height="15" rx="2.25" />
      <path d="M9 4.5v15" />
    </svg>
    """
  end

  attr :item, :map, required: true
  attr :current, :any, default: nil

  # A row of a space's tree: a folder, or a page, as a link.
  defp tree_item(%{item: %{kind: "folder", record: folder}} = assigns) do
    assigns = assign(assigns, :folder, folder)

    ~H"""
    <.link
      navigate={~p"/spaces/#{@folder.space_id}/folders/#{@folder.id}"}
      class={["sidebar-folder-link", @current == {:folder, @folder.id} && "is-current"]}
    >
      <.icon name="hero-folder" class="size-4" />
      <span>{@folder.name}</span>
    </.link>
    """
  end

  defp tree_item(%{item: %{record: page}} = assigns) do
    assigns = assign(assigns, :page, page)

    ~H"""
    <.link
      navigate={~p"/pages/#{@page.id}"}
      class={["sidebar-page", @current == {:page, @page.id} && "is-current"]}
    >
      <.icon name={page_icon(@page.kind)} class="size-4" />
      <span>{@page.title}</span>
    </.link>
    """
  end

  defp label(%{kind: "folder", record: folder}), do: folder.name
  defp label(%{record: page}), do: page.title

  @doc "The icon of a space."
  def space_icon(%{kind: "general"}), do: "hero-building-office-2"
  def space_icon(%{kind: "private"}), do: "hero-lock-closed"
  def space_icon(_team), do: "hero-user-group"

  @doc "The icon of a page of a kind."
  def page_icon("board"), do: "hero-rectangle-group"
  def page_icon("table"), do: "hero-table-cells"
  def page_icon("database"), do: "hero-circle-stack"
  def page_icon(_text), do: "hero-document-text"
end
