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
      |> assign(name: name, search: "", day: nil, page_title: "Notebook")
      |> load_page(params)
      |> page_actions()

    {:ok, socket}
  end

  # The command palette's actions of what this LiveView shows; the actions
  # of the whole notebook are in NotebookWeb.Commands.
  defp page_actions(%{assigns: %{live_action: :index}} = socket) do
    today = socket.assigns.today

    days =
      for offset <- 0..6 do
        day = Date.add(today, offset)

        Jumon.action("day-#{day}", day_name(day, today),
          icon: "hero-calendar",
          subtitle: Calendar.strftime(day, "%-d %B"),
          run: &show_day(&1, day)
        )
      end

    Jumon.Live.put_actions(socket, [
      Jumon.action(:show_day, "Show a day",
        section: "The notebook's days",
        icon: "hero-calendar-days",
        keywords: ~w(agenda calendar due review),
        shortcut: "g d",
        children: days
      ),
      Jumon.action(:all_days, "Show every page",
        section: "The notebook's days",
        icon: "hero-squares-2x2",
        run: &show_day(&1, nil)
      )
    ])
  end

  defp page_actions(%{assigns: %{live_action: :show, page: page}} = socket) do
    Jumon.Live.put_actions(socket, [
      Jumon.action(:edit_page, "Edit together",
        section: page.title,
        icon: "hero-pencil-square",
        shortcut: "e",
        navigate: ~p"/pages/#{page.id}/edit"
      ),
      Jumon.action(:rename_page, "Rename this page…",
        section: page.title,
        icon: "hero-pencil",
        args: [title: [type: :text, placeholder: page.title, max_length: 160]],
        run: &rename_page/2
      ),
      Jumon.action(:due_page, "Set the due date…",
        section: page.title,
        icon: "hero-flag",
        keywords: ~w(deadline date),
        args: [
          due: [label: "Due", options: due_options(Koyomi.Rules.today(Page.review_rules()), page)]
        ],
        run: &set_due/2
      ),
      Jumon.action(:copy_link, "Copy link",
        section: page.title,
        icon: "hero-link",
        copy: url(~p"/pages/#{page.id}")
      ),
      Jumon.action(:copy_markdown, "Copy Markdown",
        section: page.title,
        icon: "hero-clipboard-document",
        copy: copy_text(page, :markdown)
      )
    ])
  end

  defp page_actions(%{assigns: %{live_action: :edit, page: page}} = socket) do
    Jumon.Live.put_actions(socket, [
      Jumon.action(:read_page, "Read this page",
        section: page.title,
        icon: "hero-book-open",
        navigate: ~p"/pages/#{page.id}"
      ),
      Jumon.action(:copy_link, "Copy link",
        section: page.title,
        icon: "hero-link",
        copy: url(~p"/pages/#{page.id}")
      )
    ])
  end

  defp page_actions(socket), do: socket

  defp due_name(day, today) do
    if Date.diff(day, today) == 14, do: "In two weeks", else: day_name(day, today)
  end

  defp day_name(day, today) do
    case Date.diff(day, today) do
      0 -> "Today"
      1 -> "Tomorrow"
      _ -> Calendar.strftime(day, "%A")
    end
  end

  # The days that a page is often due: soon, at the end of a week, or not.
  defp due_options(today, page) do
    next = fn weekday -> Date.add(today, rem(weekday - Date.day_of_week(today) + 6, 7) + 1) end

    days =
      [today, Date.add(today, 1), next.(5), next.(1), Date.add(today, 14)]
      |> Enum.uniq()
      |> Enum.sort(Date)

    options =
      for day <- days do
        Jumon.action(Date.to_iso8601(day), due_name(day, today),
          icon: "hero-calendar",
          subtitle: Calendar.strftime(day, "%-d %B")
        )
      end

    if page.due_on,
      do: options ++ [Jumon.action("none", "No due date", icon: "hero-x-mark")],
      else: options
  end

  defp show_day(socket, day) do
    socket
    |> assign(day: day)
    |> list_pages()
    |> Koyomi.Live.push_value("notebook-calendar", day)
  end

  defp rename_page(%{title: title}, socket),
    do: update_page(socket, %{"title" => title}, "Page renamed")

  defp set_due(%{due: "none"}, socket),
    do: update_page(socket, %{"due_on" => nil}, "Due date removed")

  defp set_due(%{due: day}, socket), do: update_page(socket, %{"due_on" => day}, "Due date set")

  defp update_page(socket, attrs, message) do
    case Pages.update(socket.assigns.page, attrs) do
      {:ok, page} ->
        socket
        |> assign(page: page, page_title: page.title, form: to_form(Pages.change(page)))
        |> page_actions()
        |> put_flash(:info, message)

      {:error, changeset} ->
        {:error, changeset_message(changeset), socket}
    end
  end

  defp changeset_message(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(&translate_error/1)
    |> Enum.map_join(". ", fn {_field, messages} -> Enum.join(messages, ", ") end)
  end

  defp load_page(socket, %{"id" => id} = params) do
    page = Pages.get!(id)

    socket =
      assign(socket,
        page: page,
        page_title: page.title,
        form: to_form(Pages.change(page)),
        # The page's room: its people and their pointers, listed and drawn
        # once for the page, and its shared text.
        grant: Issho.Live.grant(Notebook.Issho, user(socket), Notebook.Collaboration.room(page)),
        collab:
          Kotoba.Collab.token(Notebook.Issho, "#{Notebook.Collaboration.room(page)}/body",
            user: user(socket),
            role: :write,
            people: false,
            undo: :page
          ),
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
      today: Koyomi.Rules.today(Page.review_rules()),
      form: to_form(Pages.change(%Page{})),
      grant: nil,
      collab: nil
    )
  end

  defp user(socket) do
    account = socket.assigns.current_scope.user
    %{id: to_string(account.id), name: socket.assigns.name, color: participant_color(account.id)}
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
            <div class="index-actions">
              <Jumon.Components.command_button id="index-commands" class="button command-trigger" />
              <.link class="button button-primary" navigate={~p"/pages/new"}>New page
              <span aria-hidden="true">↗</span></.link>
            </div>
          </div>
          <div class="index-body">
            <aside class="agenda" aria-labelledby="agenda-label">
              <p id="agenda-label" class="field-label">The notebook's days</p>
              <.calendar
                id="notebook-calendar"
                label="The notebook's days"
                select="date"
                on_change="day"
                days
                holidays="PT"
                typing={false}
              />
              <ul class="agenda-legend">
                <li><i data-tone="accent"></i>Due</li>
                <li><i data-tone="success"></i>Review</li>
                <li><i data-tone="warning"></i>Revisit</li>
                <li><i data-tone="muted"></i>Covered</li>
              </ul>
            </aside>
            <div class="page-list">
              <div :if={@day} class="day-filter">
                <p>
                  <span class="eyebrow">On {Calendar.strftime(@day, "%A")}</span>
                  <strong>{Calendar.strftime(@day, "%-d %B %Y")}</strong>
                  · {page_count(length(@pages))}
                </p>
                <button type="button" class="copy-action" phx-click="all_days">Show every page</button>
              </div>
              <div :if={@pages == [] and @day} class="empty-state">
                <span class="empty-mark">✳</span>
                <h2>Nothing on this day.</h2>
                <p>Give a page a due date, the days it covers, a review or a revisit.</p>
              </div>
              <div :if={@pages == [] and is_nil(@day)} class="empty-state">
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
                  <span :if={page.due_on} class={["page-due", due_tone(page.due_on, @today)]}>
                    Due {Calendar.strftime(page.due_on, "%-d %b")}
                  </span>
                  <span :if={page.author} class="page-author">{page.author.name}</span>
                  <time>{Calendar.strftime(page.updated_at, "%d %b %Y")}</time><span aria-hidden="true">↗</span>
                </div>
              </.link>
            </div>
          </div>
        </div>

        <div :if={@live_action == :new} class="page-view">
          <div class="page-nav">
            <.link navigate={~p"/"}>← All pages</.link>
            <div class="page-nav-end">
              <Jumon.Components.command_button id="page-commands" class="command-link" /><span>NEW PAGE</span>
            </div>
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
            <.page_dates form={@form} />
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
            <.link navigate={~p"/"}>← All pages</.link>
            <div class="page-nav-end">
              <Issho.Components.people id="page-people" grant={@grant} label="On this page" />
              <Jumon.Components.command_button id="page-commands" class="command-link" /><span>PAGE / {@page.id}</span>
            </div>
          </div>
          <Issho.Components.pointers id="page-pointers" grant={@grant} />
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
          <dl :if={@live_action == :show and dated?(@page)} class="page-dates-summary">
            <div :if={@page.due_on}>
              <dt>Due</dt>
              <dd>{Calendar.strftime(@page.due_on, "%A, %-d %B %Y")}</dd>
            </div>
            <div :if={@page.covers}>
              <dt>Covers</dt>
              <dd>{span(@page.covers)}</dd>
            </div>
            <div :if={@page.review_at}>
              <dt>Review together</dt>
              <dd>{review_time(@page.review_at)}</dd>
            </div>
            <div :if={@page.revisit}>
              <dt>Revisit</dt>
              <dd>
                {Koyomi.Recurrence.describe(@page.revisit, "en", start: Pages.revisit_start(@page))}
                <span :if={Pages.next_revisit(@page)} class="page-dates-next">
                  Next on {Calendar.strftime(Pages.next_revisit(@page), "%-d %B %Y")}
                </span>
              </dd>
            </div>
          </dl>
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
            <.page_dates form={@form} />
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
      <Jumon.Components.command_palette
        jumon={@jumon}
        placeholder="Search pages, or type a command…"
        icons={~w(hero-document-text hero-pencil-square)}
      >
        <:icon :let={name}><.icon name={name} class="size-4" /></:icon>
      </Jumon.Components.command_palette>
    </div>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true

  # The page's dates. Each picker posts with the form, so the form's own
  # validate and save events have the values, and the changeset checks
  # the rules the pickers show (Page.covers_rules/0, Page.review_rules/0).
  defp page_dates(assigns) do
    ~H"""
    <fieldset class="page-dates">
      <legend class="field-label">Dates</legend>
      <div class="page-dates-grid">
        <div class="page-date">
          <span id="due-label" class="page-date-label">Due</span>
          <.date_picker
            field={@form[:due_on]}
            label_id="due-label"
            presets={[:today, :tomorrow, {:in, 1, :week}, {:in, 1, :month}]}
          />
          <.date_errors field={@form[:due_on]} />
        </div>
        <div class="page-date">
          <span id="covers-label" class="page-date-label">Covers</span>
          <.date_range_picker
            field={@form[:covers]}
            label_id="covers-label"
            rules={Page.covers_rules()}
            months={2}
            presets={[:this_week, :next_week, :this_month, {:last, 7, :days}]}
          />
          <.date_errors field={@form[:covers]} />
        </div>
        <div class="page-date">
          <span id="review-label" class="page-date-label">Review together</span>
          <.datetime_picker
            field={@form[:review_at]}
            label_id="review-label"
            rules={Page.review_rules()}
            time_zone={Pages.time_zone()}
            slots
          />
          <.date_errors field={@form[:review_at]} />
        </div>
        <div class="page-date">
          <span id="revisit-label" class="page-date-label">Revisit</span>
          <.recurrence_picker
            field={@form[:revisit]}
            label_id="revisit-label"
            start={revisit_start(@form[:due_on].value)}
          />
          <.date_errors field={@form[:revisit]} />
        </div>
      </div>
    </fieldset>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true

  defp date_errors(assigns) do
    ~H"""
    <p :for={msg <- date_error_messages(@field)} class="page-date-error">{msg}</p>
    """
  end

  defp date_error_messages(field) do
    if Phoenix.Component.used_input?(field),
      do: Enum.map(field.errors, &translate_error/1),
      else: []
  end

  # The revisits start on the due day, as the reader counts them.
  defp revisit_start(%Date{} = date), do: date

  defp revisit_start(text) when is_binary(text) do
    case Date.from_iso8601(text) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end

  defp revisit_start(_other), do: nil

  defp dated?(page), do: Enum.any?([page.due_on, page.covers, page.review_at, page.revisit])

  defp span(%Date.Range{first: first, last: last} = range) do
    days = Enum.count(range)
    from = if first.year == last.year, do: "%-d %B", else: "%-d %B %Y"

    "#{Calendar.strftime(first, from)} – #{Calendar.strftime(last, "%-d %B %Y")} · " <>
      "#{days} #{if days == 1, do: "day", else: "days"}"
  end

  defp review_time(at) do
    local = Pages.local(at)
    city = Pages.time_zone() |> String.split("/") |> List.last() |> String.replace("_", " ")
    Calendar.strftime(local, "%A, %-d %B %Y at %H:%M") <> " (#{city} time)"
  end

  defp due_tone(due, today) do
    case Date.compare(due, today) do
      :lt -> "page-due-past"
      :eq -> "page-due-today"
      :gt -> nil
    end
  end

  defp page_count(1), do: "1 page"
  defp page_count(n), do: "#{n} pages"

  @tones %{due: :accent, review: :success, revisit: :warning, covers: :muted}
  @kinds %{due: "Due", review: "Review", revisit: "Revisit", covers: "Covers"}

  # The index calendar's days: a mark for each thing a page has on the
  # day, and the titles for screen readers and the hover.
  defp agenda_days(range) do
    for {day, items} <- Pages.agenda(Pages.list(), range), into: %{} do
      title = Enum.map_join(items, "; ", fn {kind, page} -> "#{@kinds[kind]}: #{page.title}" end)
      {day, [marks: Enum.map(items, fn {kind, _page} -> @tones[kind] end), title: title]}
    end
  end

  defp list_pages(socket) do
    pages = Pages.list(socket.assigns.search)
    pages = if socket.assigns.day, do: Pages.on_day(pages, socket.assigns.day), else: pages
    assign(socket, pages: pages)
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
    do: {:noreply, socket |> assign(search: query) |> list_pages()}

  # A day picked in the index calendar shows the pages that have something
  # on it; picking it again clears it.
  def handle_event("day", %{"value" => value}, socket) do
    day =
      case Date.from_iso8601(value || "") do
        {:ok, day} -> day
        {:error, _reason} -> nil
      end

    {:noreply, socket |> assign(day: day) |> list_pages()}
  end

  def handle_event("all_days", _params, socket) do
    {:noreply,
     socket
     |> assign(day: nil)
     |> list_pages()
     |> Koyomi.Live.push_value("notebook-calendar", nil)}
  end

  def handle_event("koyomi:days", %{"id" => "notebook-calendar"} = params, socket),
    do: Koyomi.Live.handle_days(socket, params, &agenda_days/1)

  # The review picker's free times; the page's own review is not taken.
  def handle_event("koyomi:days", %{"id" => "page_review_at_picker"} = params, socket) do
    page_id = socket.assigns.page && socket.assigns.page.id
    Koyomi.Live.handle_days(socket, params, &Pages.review_slots(&1, page_id))
  end

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
             Notebook.Issho,
             "#{Notebook.Collaboration.room(socket.assigns.page)}/body",
             revision
           ),
         {:ok, page} <-
           Pages.update(socket.assigns.page, page_params(params, content)) do
      {:noreply,
       socket
       |> assign(page: page)
       |> put_flash(:info, "Page published")
       |> push_navigate(to: ~p"/pages/#{page.id}")}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(form: to_form(changeset))
         |> put_flash(:error, "Check the page's dates, then publish again.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not publish this revision. Please retry.")}
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

  defp handle_progress(:attachments, entry, socket) do
    if entry.done?,
      do: {:noreply, Kotoba.Live.consume_uploads(socket, :attachments, "body-editor")},
      else: {:noreply, socket}
  end

  # The title and the dates come from the form; the body is the accepted
  # revision of the collaboration.
  defp page_params(params, content) do
    params
    |> Map.take(~w(title due_on covers review_at revisit))
    |> Map.put("body", content)
  end
end
