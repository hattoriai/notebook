defmodule NotebookWeb.NotebookLive do
  use NotebookWeb, :live_view

  alias Notebook.Pages
  alias Notebook.Pages.Page

  @impl true
  def mount(params, _session, socket) do
    user = socket.assigns.current_scope.user
    name = user.name

    socket =
      socket
      |> assign(name: name, search: "", page_title: "Notebook")
      |> load_page(params)

    {:ok, socket}
  end

  defp load_page(socket, %{"id" => id} = params) do
    page = Pages.get!(id)

    socket =
      assign(socket,
        page: page,
        page_title: page.title,
        form: to_form(Pages.change(page)),
        collab: Kotoba.Collab.token(socket, to_string(id), user: user(socket), role: :write),
        editing?: Map.has_key?(params, "edit")
      )

    allow_upload(socket, :attachments,
      accept: ~w(.png .jpg .jpeg .gif .webp .pdf .mp4 .webm),
      max_file_size: 100_000_000,
      max_entries: 12,
      auto_upload: true,
      progress: &handle_progress/3
    )
  end

  defp load_page(socket, _params) do
    assign(socket,
      pages: Pages.list(),
      page: nil,
      form: to_form(Pages.change(%Page{})),
      collab: nil
    )
  end

  defp user(socket) do
    account = socket.assigns.current_scope.user
    %{id: account.id, name: socket.assigns.name, color: participant_color(account.id)}
  end

  # Each writer keeps one color, so that two cursors never look the same.
  @participant_colors ~w(#a45537 #3f6f8f #5d7f3a #8b4f86 #b07a1f #2f7d74 #9b3d4f #56608f)

  defp participant_color(id),
    do: Enum.at(@participant_colors, rem(id, length(@participant_colors)))

  defp prompts do
    [
      {"@", :people, [search: &Notebook.People.search/1, label: "People", spaces: true]},
      {"#", :pages, [search: &Pages.mentions/1, label: "Pages", spaces: true]}
    ]
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :prompts, prompts())

    ~H"""
    <div class="notebook-shell">
      <main class="notebook-main">
        <div class="flash-area"><Layouts.flash_group flash={@flash} /></div>

        <div :if={@live_action == :index} class="index-page">
          <div class="index-intro">
            <p class="eyebrow">Your shared notebook</p>
            <h1>Good ideas deserve<br />a place to land.</h1>
            <p>Write together, collect the details, and come back to them later.</p>
          </div>
          <div class="index-tools">
            <form id="page-search" phx-change="search" role="search">
              <label for="search">Find a page</label>
              <input
                id="search"
                type="search"
                name="query"
                value={@search}
                placeholder="Search titles and words…"
                phx-debounce="250"
              />
            </form>
            <.link class="button button-primary" navigate={~p"/pages/new"}>New page
            <span aria-hidden="true">↗</span></.link>
          </div>
          <div class="page-list">
            <div :if={@pages == []} class="empty-state">
              <span class="empty-mark">✳</span>
              <h2>Start with a blank page.</h2>
              <p>Try a heading, mention a person, or drop in an image or PDF.</p>
            </div>
            <.link
              :for={page <- @pages}
              class="page-row"
              navigate={~p"/pages/#{page.id}"}
            >
              <div>
                <span class="page-kicker">PAGE / {page.id}</span><h2>{page.title}</h2><p>
                  {excerpt(page.body)}
                </p>
              </div>
              <div class="page-meta">
                <span :if={page.author} class="page-author">{page.author.name}</span>
                <time>{Calendar.strftime(page.updated_at, "%d %b %Y")}</time><span aria-hidden="true">↗</span>
              </div>
            </.link>
          </div>
        </div>

        <div :if={@live_action == :new} class="page-view">
          <div class="page-nav">
            <.link navigate={~p"/"}>← All pages</.link><span>NEW PAGE</span>
          </div>
          <div class="page-heading">
            <p class="eyebrow">A fresh page</p><h1>What are we writing?</h1>
          </div>
          <.form
            for={@form}
            id="new-page"
            phx-change="validate"
            phx-submit="create"
            class="page-form"
          >
            <label for="page_title" class="field-label">Title</label>
            <input
              id="page_title"
              type="text"
              name="page[title]"
              value={@form[:title].value}
              placeholder="Give this page a name"
              required
              maxlength="160"
              autofocus
            />
            <label class="field-label" for="new-body">Body</label>
            <.kotoba
              field={@form[:body]}
              id="new-body"
              label="Body"
              prompts={@prompts}
              extensions={[~p"/assets/kotoba/extensions/callout.js"]}
              placeholder="Start writing…"
              selection_menu
            />
            <button class="button button-primary" type="submit">Create page</button>
          </.form>
        </div>

        <div :if={@live_action in [:show, :edit]} class="page-view">
          <div class="page-nav">
            <.link navigate={~p"/"}>← All pages</.link><span>PAGE / {@page.id}</span>
          </div>
          <div class="page-heading">
            <p class="eyebrow">Shared page</p>
            <h1>{@page.title}</h1>
            <p :if={@live_action == :show}>
              <span :if={@page.author} class="page-byline">By {@page.author.name} ·</span>
              Updated {Calendar.strftime(@page.updated_at, "%-d %B %Y")}
            </p>
            <p :if={@live_action == :edit}>
              Invite someone to sign in and open this page to write together.
            </p>
          </div>
          <div :if={@live_action == :show} class="reader-actions">
            <.link
              class="button button-primary"
              navigate={~p"/pages/#{@page.id}/edit"}
            >Edit together</.link>
            <button
              :for={{format, label} <- [markdown: "Copy Markdown", text: "Copy text"]}
              id={"copy-#{format}"}
              type="button"
              class="copy-action"
              phx-hook=".Copy"
              data-format={format}
              data-copy={copy_text(@page, format)}
            >
              <.icon name="hero-clipboard-document" class="copy-icon size-4" />
              <.icon name="hero-check" class="copied-icon size-4" />
              {label}
            </button>
          </div>
          <script :type={Phoenix.LiveView.ColocatedHook} name=".Copy">
            // Writes the button's text to the clipboard within the click, as
            // Safari requires, then asks the server for the toast.
            export default {
              mounted() {
                this.el.addEventListener("click", async () => {
                  const format = this.el.dataset.format
                  try {
                    await navigator.clipboard.writeText(this.el.dataset.copy ?? "")
                    this.el.dataset.copied = "true"
                    clearTimeout(this.timer)
                    this.timer = setTimeout(() => delete this.el.dataset.copied, 1600)
                    this.pushEvent("copied", {format})
                  } catch (_error) {
                    this.pushEvent("copy_failed", {format})
                  }
                })
              },
              destroyed() {
                clearTimeout(this.timer)
              }
            }
          </script>
          <article :if={@live_action == :show} class="page-body">
            <.kotoba_content content={@page.body} />
          </article>
          <.form
            :if={@live_action == :edit}
            for={@form}
            id="page-form"
            phx-change="validate"
            phx-submit="save"
            class="page-form"
          >
            <label class="field-label" for="page_title">Title</label>
            <input
              id="page_title"
              name="page[title]"
              value={@form[:title].value}
              maxlength="160"
              required
            />
            <label class="field-label" for="body-editor">Body · live collaboration</label>
            <.kotoba
              field={@form[:body]}
              id="body-editor"
              label="Body"
              collab={@collab}
              uploads={@uploads.attachments}
              prompts={@prompts}
              extensions={[~p"/assets/kotoba/extensions/callout.js"]}
              placeholder="Write something worth keeping…"
            >
              <:selection>
                <.kotoba_selection_menu id="body-selection-menu" class="notebook-selection-menu">
                  <:button command="bold"><.icon name="hero-bold" class="size-4" /></:button>
                  <:button command="italic"><.icon name="hero-italic" class="size-4" /></:button>
                  <:button command="underline">
                    <.icon name="hero-underline" class="size-4" />
                  </:button>
                  <:button command="strikethrough">
                    <.icon name="hero-strikethrough" class="size-4" />
                  </:button>
                  <:button command="code"><.icon name="hero-code-bracket" class="size-4" /></:button>
                  <:button command="highlight" label="Color and highlight">
                    <.icon name="hero-swatch" class="size-4" />
                  </:button>
                  <:button command="link" label="Add a link">
                    <.icon name="hero-link" class="size-4" />
                  </:button>
                  <:button command="h2" label="Heading"><.icon name="hero-h2" class="size-4" /></:button>
                  <:button command="quote">
                    <.icon name="hero-chat-bubble-bottom-center-text" class="size-4" />
                  </:button>
                  <:button command="callout:toggle" label="Callout">
                    <.icon name="hero-light-bulb" class="size-4" />
                  </:button>
                </.kotoba_selection_menu>
              </:selection>
            </.kotoba>
            <div class="form-actions">
              <button class="button button-primary" type="submit">Publish page</button><.link navigate={
                ~p"/pages/#{@page.id}"
              }>Read page</.link>
            </div>
          </.form>
        </div>
      </main>
      <footer class="site-footer">Notebook <span>·</span> Made with Kotoba</footer>
    </div>
    """
  end

  # The Markdown or the plain text of a page, for the copy buttons.
  defp copy_text(%{body: nil}, _format), do: ""
  defp copy_text(%{body: %Kotoba.Content{text: text}}, :text), do: text || ""

  defp copy_text(%{body: %Kotoba.Content{doc: doc}}, :markdown) do
    case Kotoba.Document.parse(doc) do
      {:ok, parsed} -> Kotoba.Renderer.to_markdown(parsed)
      {:error, _messages} -> ""
    end
  end

  defp format_name("markdown"), do: "Markdown"
  defp format_name(_text), do: "Plain text"

  defp excerpt(nil), do: "A fresh page, ready for words."

  defp excerpt(%Kotoba.Content{text: text}) when text in [nil, ""],
    do: "A fresh page, ready for words."

  # At most 160 characters, cut at the end of a word.
  defp excerpt(%Kotoba.Content{text: text}) do
    text = text |> String.replace(~r/\s+/, " ") |> String.trim()

    if String.length(text) <= 160,
      do: text,
      else: (text |> String.slice(0, 160) |> String.replace(~r/\s+\S*\z/, "")) <> "…"
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket),
    do: {:noreply, assign(socket, search: query, pages: Pages.list(query))}

  def handle_event("validate", %{"page" => params}, socket) do
    socket =
      if socket.assigns.page,
        do: Kotoba.Live.consume_uploads(socket, :attachments, "body-editor"),
        else: socket

    page = socket.assigns.page || %Page{}

    {:noreply, assign(socket, form: to_form(Pages.change(page, params), action: :validate))}
  end

  def handle_event("create", %{"page" => params}, socket) do
    case Pages.create(socket.assigns.current_scope, params) do
      {:ok, page} ->
        {:noreply, push_navigate(socket, to: ~p"/pages/#{page.id}/edit")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event(
        "save",
        %{"page" => params, "kotoba_collab" => %{"body-editor" => json}},
        socket
      ) do
    with {:ok, revision} <- JSON.decode(json),
         {:ok, content} <-
           Kotoba.Collab.content(
             Notebook.CollabSupervisor,
             to_string(socket.assigns.page.id),
             revision
           ),
         {:ok, page} <-
           Pages.update(socket.assigns.page, %{title: params["title"], body: content}) do
      {:noreply,
       socket
       |> assign(page: page)
       |> put_flash(:info, "Page published")
       |> push_navigate(to: ~p"/pages/#{page.id}")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not publish this revision. Please retry.")}
    end
  end

  def handle_event("copied", %{"format" => format}, socket),
    do: {:noreply, put_flash(socket, :info, "#{format_name(format)} copied to your clipboard")}

  def handle_event("copy_failed", %{"format" => format}, socket) do
    {:noreply,
     put_flash(
       socket,
       :error,
       "Could not copy the #{String.downcase(format_name(format))}. Allow clipboard access and try again."
     )}
  end

  def handle_event("kotoba:prompt", params, socket),
    do: {:noreply, Kotoba.Live.handle_prompt(socket, params, prompts())}

  def handle_event("kotoba:collab_token", %{"id" => "body-editor", "document_id" => id}, socket) do
    if socket.assigns.page && to_string(socket.assigns.page.id) == id do
      {:reply, Kotoba.Collab.token(socket, id, user: user(socket), role: :write), socket}
    else
      {:reply, %{}, socket}
    end
  end

  defp handle_progress(:attachments, entry, socket) do
    if entry.done?,
      do: {:noreply, Kotoba.Live.consume_uploads(socket, :attachments, "body-editor")},
      else: {:noreply, socket}
  end
end
