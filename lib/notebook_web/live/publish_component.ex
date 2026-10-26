defmodule NotebookWeb.PublishComponent do
  @moduledoc """
  The Publish dialog of a page, or of a folder as a blog
  (`Notebook.Publishing`): its address once published, its slug, and the
  way to publish it, change its slug, or take it back.
  """
  use NotebookWeb, :live_component

  alias Notebook.Pages.Page
  alias Notebook.Publishing

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    resource = socket.assigns.resource

    {:ok,
     assign(socket,
       slug: Publishing.suggest_slug(resource),
       error: nil,
       url: Publishing.published?(resource) && Publishing.url(resource)
     )}
  end

  @impl true
  def handle_event("publish", %{"slug" => slug}, socket) do
    %{scope: scope, resource: resource} = socket.assigns
    {kind, id} = kind(resource)

    # The action (Notebook.Actions.Publish), a person's only.
    case NotebookWeb.Act.act(scope, Notebook.Actions.Publish, %{kind: kind, id: id, slug: slug}) do
      {:ok, %{result: resource}} ->
        send(self(), {:published, resource})

        {:noreply,
         assign(socket,
           resource: resource,
           slug: resource.slug,
           url: Publishing.url(resource),
           error: nil
         )}

      {:error, message} when is_binary(message) ->
        {:noreply, assign(socket, error: message, slug: slug)}

      {:error, _other} ->
        {:noreply, assign(socket, error: "It can't be published as “#{slug}”.", slug: slug)}
    end
  end

  def handle_event("unpublish", _params, socket) do
    {kind, id} = kind(socket.assigns.resource)

    {:ok, %{result: resource}} =
      NotebookWeb.Act.act(socket.assigns.scope, Notebook.Actions.Unpublish, %{kind: kind, id: id})

    send(self(), {:published, resource})
    {:noreply, assign(socket, resource: resource, url: nil)}
  end

  defp kind(%Page{id: id}), do: {"page", id}
  defp kind(%{id: id}), do: {"folder", id}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="share-backdrop" phx-window-keydown="publish_close" phx-key="Escape">
      <section
        id={@id}
        class="share-dialog publish-dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby={@id <> "-title"}
        phx-click-away="publish_close"
      >
        <header class="share-head">
          <div>
            <p class="eyebrow">{if page?(@resource), do: "Page", else: "Folder"}</p>
            <h2 id={@id <> "-title"}>
              {if page?(@resource),
                do: "Publish #{@resource.title}",
                else: "Publish #{@resource.name} as a blog"}
            </h2>
          </div>
          <button type="button" class="share-close" phx-click="publish_close" aria-label="Close">
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </header>

        <p class="publish-about">
          {about(@resource)}
        </p>

        <div :if={@url} class="publish-live">
          <span class="share-avatar is-published"><.icon name="hero-globe-alt" class="size-4" /></span>
          <span class="share-who">
            Published <small>since {Calendar.strftime(@resource.published_at, "%-d %B %Y")}</small>
          </span>
          <a class="button" href={@url} target="_blank" rel="noopener">Open ↗</a>
        </div>
        <div :if={@url} class="share-url">
          <input id={@id <> "-url"} type="text" value={@url} readonly aria-label="Its address" />
          <button
            type="button"
            class="button"
            phx-click={JS.dispatch("notebook:copy", to: "##{@id}-url")}
          >
            Copy
          </button>
        </div>

        <form id={@id <> "-form"} class="publish-form" phx-submit="publish" phx-target={@myself}>
          <label for={@id <> "-slug"}>Its address ends with</label>
          <div class="publish-slug">
            <span>{prefix(@resource, @scope.user)}</span>
            <input
              id={@id <> "-slug"}
              name="slug"
              value={@slug}
              autocomplete="off"
              spellcheck="false"
            />
          </div>
          <p :if={@error} class="publish-error">{@error}</p>
          <div class="publish-actions">
            <button type="submit" class="button button-primary">
              {if @url, do: "Save the address", else: "Publish"}
            </button>
            <button
              :if={@url}
              type="button"
              class="copy-action"
              phx-click="unpublish"
              phx-target={@myself}
            >
              <.icon name="hero-eye-slash" class="size-4" /> Unpublish
            </button>
          </div>
        </form>
      </section>
    </div>
    """
  end

  defp page?(resource), do: match?(%Page{}, resource)

  defp about(%Page{}),
    do:
      "Anyone may read it at its address, live as you change it: its charts and tables too. Comments, and who's on it, stay in the notebook."

  defp about(_folder),
    do:
      "Its published pages become posts, the latest first, with an RSS feed. Publish each page you want in it."

  # Its address up to its slug: the publishing address and prefix, the
  # handle of who publishes it (by person), its blog's slug.
  defp prefix(resource, user) do
    resource = %{resource | slug: "", published_by: user, published_by_id: user.id}
    path = Publishing.path(resource) |> String.trim_trailing("/")
    host = URI.parse(Publishing.config().url).host
    host <> path <> "/"
  end
end
