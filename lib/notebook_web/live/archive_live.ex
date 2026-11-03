defmodule NotebookWeb.ArchiveLive do
  @moduledoc """
  The archived pages the person may read: out of the sidebar and the
  lists, never lost. An editor of a page's space brings it back. And the
  archived spaces the person manages, with all their pages: restored, or
  deleted for good.
  """
  use NotebookWeb, :live_view

  alias Notebook.{Pages, Spaces}
  alias Notebook.Spaces.Space
  alias NotebookWeb.Sidebar

  @impl true
  def mount(_params, _session, socket),
    do: {:ok, socket |> assign(page_title: "Archive") |> load()}

  defp load(socket) do
    scope = socket.assigns.current_scope
    pages = Pages.list(scope, archived: true)

    assign(socket,
      pages: Enum.map(pages, &{&1, Pages.allowed?(scope, :edit, &1)}),
      spaces: Spaces.archived(scope)
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="notebook-shell notebook-with-sidebar">
      <.sidebar tree={@tree} chime={@chime} shared={@shared} current={:archive} />
      <main class="notebook-main">
        <div class="flash-area"><Layouts.flash_group flash={@flash} /></div>
        <div class="space-view">
          <div class="page-heading">
            <p class="eyebrow"><.icon name="hero-archive-box" class="size-3.5" /> Out of the way</p>
            <h1>Archive</h1>
            <p>
              Pages you put away. They keep their words, their comments and their place, and come back when you restore them.
            </p>
          </div>
          <section :if={@spaces != []} class="archive-spaces" id="archived-spaces">
            <h2 class="archive-heading">Spaces</h2>
            <div class="page-list">
              <div
                :for={space <- @spaces}
                class="page-row archive-row"
                id={"archived-space-#{space.id}"}
              >
                <div>
                  <span class="page-kicker">
                    <Icons.named name={Sidebar.space_icon(space)} class="size-3.5" /> Space
                  </span>
                  <h2>{space.name}</h2>
                </div>
                <div class="page-meta">
                  <time>Archived {Calendar.strftime(space.archived_at, "%-d %b %Y")}</time>
                  <button
                    type="button"
                    class="copy-action"
                    phx-click="restore_space"
                    phx-value-id={space.id}
                  >
                    <.icon name="hero-arrow-uturn-left" class="size-4" /> Restore
                  </button>
                  <button
                    type="button"
                    class="copy-action danger"
                    phx-click="delete_space"
                    phx-value-id={space.id}
                    data-confirm={"Delete #{space.name} for good, with all its pages? It cannot be undone."}
                  >
                    <.icon name="hero-trash" class="size-4" /> Delete forever
                  </button>
                </div>
              </div>
            </div>
            <h2 class="archive-heading">Pages</h2>
          </section>
          <div class="page-list">
            <div :if={@pages == []} class="empty-state">
              <span class="empty-mark">✳</span>
              <h2>Nothing archived.</h2>
              <p>Archive a page from its commands (⌘K) when it has done its work.</p>
            </div>
            <div
              :for={{page, can_edit?} <- @pages}
              class="page-row archive-row"
              id={"archived-#{page.id}"}
            >
              <.link navigate={~p"/pages/#{page}"}>
                <span class="page-kicker">
                  <.icon name={Sidebar.page_icon(page.kind)} class="size-3.5" /> {page.space.name}
                </span>
                <h2>{page.title}</h2>
              </.link>
              <div class="page-meta">
                <time>Archived {Calendar.strftime(page.archived_at, "%-d %b %Y")}</time>
                <button
                  :if={can_edit?}
                  type="button"
                  class="copy-action"
                  phx-click="restore"
                  phx-value-id={page.id}
                >
                  <.icon name="hero-arrow-uturn-left" class="size-4" /> Restore
                </button>
              </div>
            </div>
          </div>
        </div>
      </main>
      <Layouts.palette jumon={@jumon} />
    </div>
    """
  end

  @impl true
  def handle_event("restore_space", %{"id" => id}, socket) do
    space = Notebook.Repo.get!(Space, id)

    case Spaces.restore(socket.assigns.current_scope, space) do
      {:ok, space} ->
        {:noreply, socket |> put_flash(:info, "#{space.name} is back, with its pages.") |> load()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "You may not restore #{space.name}.")}
    end
  end

  def handle_event("delete_space", %{"id" => id}, socket) do
    space = Notebook.Repo.get!(Space, id)

    case Spaces.delete(socket.assigns.current_scope, space) do
      {:ok, _space} ->
        {:noreply,
         socket |> put_flash(:info, "#{space.name} is deleted, with its pages.") |> load()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "You may not delete #{space.name}.")}
    end
  end

  def handle_event("restore", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    page = Pages.get!(scope, id)

    case Pages.restore(scope, page) do
      {:ok, page} ->
        {:noreply,
         socket |> put_flash(:info, "#{page.title} is back in #{page.space.name}.") |> load()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "You may not restore #{page.title}.")}
    end
  end
end
