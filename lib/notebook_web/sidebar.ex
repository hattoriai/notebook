defmodule NotebookWeb.Sidebar do
  @moduledoc """
  The notebook's sidebar: Home, the spaces the person may read, each with
  its folders and pages, and the Archive. Every LiveView of the notebook
  mounts it (`on_mount`): it loads the person's tree, and loads it again
  when someone makes, renames, moves or archives a page, a folder or a
  space (`Notebook.Spaces.subscribe_tree/0`), so that it is the same for
  everyone.
  """
  use NotebookWeb, :html

  import Phoenix.LiveView

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

    {:cont, socket}
  end

  @doc "Loads the person's tree again, after a change this LiveView made."
  def assign_tree(socket), do: assign(socket, :tree, Spaces.tree(socket.assigns.current_scope))

  attr :tree, :list, required: true

  attr :current, :any,
    default: nil,
    doc: "what is open: {:page, id}, {:space, id}, {:folder, id}, :home or :archive"

  def sidebar(assigns) do
    ~H"""
    <nav id="sidebar" class="sidebar" aria-label="Spaces">
      <div class="sidebar-top">
        <.link navigate={~p"/"} class={["sidebar-link", @current == :home && "is-current"]}>
          <.icon name="hero-home" class="size-4" /> Home
        </.link>
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
        <ul class="sidebar-tree">
          <li :for={folder <- node.folders}>
            <.folder_branch node={folder} current={@current} />
          </li>
          <li :for={page <- node.pages}>
            <.page_link page={page} current={@current} />
          </li>
          <li :if={node.folders == [] and node.pages == []} class="sidebar-empty">No pages yet</li>
        </ul>
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

  attr :node, :map, required: true
  attr :current, :any, default: nil

  defp folder_branch(assigns) do
    ~H"""
    <details class="sidebar-folder" open>
      <summary class={@current == {:folder, @node.folder.id} && "is-current"}>
        <.icon name="hero-folder" class="size-4" />
        <.link navigate={~p"/spaces/#{@node.folder.space_id}/folders/#{@node.folder.id}"}>
          {@node.folder.name}
        </.link>
      </summary>
      <ul class="sidebar-tree">
        <li :for={child <- @node.folders}><.folder_branch node={child} current={@current} /></li>
        <li :for={page <- @node.pages}><.page_link page={page} current={@current} /></li>
      </ul>
    </details>
    """
  end

  attr :page, :map, required: true
  attr :current, :any, default: nil

  defp page_link(assigns) do
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

  @doc "The icon of a space."
  def space_icon(%{kind: "general"}), do: "hero-building-office-2"
  def space_icon(%{kind: "private"}), do: "hero-lock-closed"
  def space_icon(_team), do: "hero-user-group"

  @doc "The icon of a page of a kind."
  def page_icon("board"), do: "hero-rectangle-group"
  def page_icon("table"), do: "hero-table-cells"
  def page_icon(_text), do: "hero-document-text"
end
