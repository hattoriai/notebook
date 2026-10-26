defmodule NotebookWeb.NotebookLive do
  use NotebookWeb, :live_view

  alias Notebook.{Charts, Databases, Pages}
  alias Notebook.Cardbox, as: Box
  alias Phoenix.LiveView.JS
  alias Notebook.Pages.Page

  @impl true
  def mount(params, _session, socket) do
    user = socket.assigns.current_scope.user
    name = user.name

    socket =
      socket
      |> assign(name: name, search: "", snippets: %{}, day: nil, page_title: "Notebook")
      |> load_page(params)

    if socket.assigns.live_action == :edit and not socket.assigns.can_edit? do
      {:ok,
       socket
       |> put_flash(:error, "You may read this page, not edit it.")
       |> push_navigate(to: ~p"/pages/#{socket.assigns.page.id}")}
    else
      {:ok, page_actions(socket)}
    end
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
    scope = socket.assigns.current_scope

    reading = [
      Jumon.action(:copy_link, "Copy link",
        section: page.title,
        icon: "hero-link",
        copy: url(~p"/pages/#{page.id}")
      ),
      Jumon.action(:copy_markdown, "Copy Markdown",
        section: page.title,
        icon: "hero-clipboard-document",
        copy: copy_text(page, :markdown, scope)
      )
    ]

    editing =
      if socket.assigns.can_edit? do
        [
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
              due: [
                label: "Due",
                options: due_options(Koyomi.Rules.today(Page.review_rules()), page)
              ]
            ],
            run: &set_due/2
          ),
          Jumon.action(:move_page, "Move to…",
            section: page.title,
            icon: "hero-arrow-right-circle",
            keywords: ~w(space folder file),
            children:
              for {label, space_id, folder_id} <- places(scope) do
                Jumon.action("move-#{space_id}-#{folder_id}", label,
                  icon: if(folder_id, do: "hero-folder", else: "hero-squares-2x2"),
                  run: &move_page(&1, space_id, folder_id)
                )
              end
          ),
          if page.archived_at do
            Jumon.action(:restore_page, "Restore this page",
              section: page.title,
              icon: "hero-arrow-uturn-left",
              run: &restore_page/1
            )
          else
            Jumon.action(:archive_page, "Archive this page",
              section: page.title,
              icon: "hero-archive-box",
              keywords: ~w(delete remove hide),
              run: &archive_page/1
            )
          end
        ]
      else
        []
      end

    Jumon.Live.put_actions(socket, editing ++ reading)
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

  # The page's own actions (Notebook.Actions), as this person: the same
  # an agent runs as a tool, in the page's room.
  defp rename_page(%{title: title}, socket),
    do: act_on_page(socket, Notebook.Actions.RenamePage, %{title: title}, "Page renamed")

  defp set_due(%{due: "none"}, socket),
    do: act_on_page(socket, Notebook.Actions.SetDueDate, %{due: "none"}, "Due date removed")

  defp set_due(%{due: day}, socket),
    do: act_on_page(socket, Notebook.Actions.SetDueDate, %{due: day}, "Due date set")

  defp act_on_page(socket, action, args, message) do
    case Issho.Live.act(action, Map.put(args, :page_id, socket.assigns.page.id)) do
      {:ok, %{result: page}} -> updated(socket, page, message)
      {:error, reason} -> {:error, Issho.Action.message(reason), socket}
    end
  end

  defp move_page(socket, space_id, folder_id) do
    case Pages.move(socket.assigns.current_scope, socket.assigns.page, space_id, folder_id) do
      {:ok, page} ->
        socket
        |> assign(page: page)
        |> page_actions()
        |> put_flash(:info, "Moved to #{place_name(page)}")

      {:error, _reason} ->
        {:error, "You may not move this page there.", socket}
    end
  end

  defp archive_page(socket) do
    {:ok, page} = Pages.archive(socket.assigns.current_scope, socket.assigns.page)

    socket
    |> assign(page: page)
    |> page_actions()
    |> put_flash(:info, "Archived. It stays in the Archive until you restore it.")
  end

  defp restore_page(socket) do
    {:ok, page} = Pages.restore(socket.assigns.current_scope, socket.assigns.page)

    socket
    |> assign(page: page)
    |> page_actions()
    |> put_flash(:info, "Restored to #{place_name(page)}")
  end

  # Where a page is, in words: its space, and its folder.
  defp place_name(%Page{space: space, folder: nil}), do: space.name
  defp place_name(%Page{space: space, folder: folder}), do: "#{space.name} / #{folder.name}"

  # The spaces the person may make pages in, and their folders: where a
  # page may go, as {label, space id, folder id}.
  defp places(scope) do
    for %{space: space} = node <- Notebook.Spaces.tree(scope),
        Notebook.Spaces.allowed?(scope, :edit, space),
        place <- [{space.name, space.id, nil} | folder_places(space, node.folders)],
        do: place
  end

  defp folder_places(space, folders) do
    Enum.flat_map(folders, fn %{folder: folder, folders: children} ->
      [
        {"#{space.name} / #{folder.name}", space.id, folder.id}
        | Enum.map(
            children,
            &{"#{space.name} / #{folder.name} / #{&1.folder.name}", space.id, &1.folder.id}
          )
      ]
    end)
  end

  # The space and folder a new page goes in: the ones in the address
  # (`?space=&folder=`), else the person's Private space.
  defp place_param(params, scope) do
    places = places(scope)
    space = params["space"] && String.to_integer(params["space"])
    folder = params["folder"] && String.to_integer(params["folder"])

    Enum.find(places, fn {_label, s, f} -> s == space and f == folder end) ||
      Enum.find(places, fn {_label, s, f} -> s == space and is_nil(f) end) ||
      {"Private", Notebook.Spaces.private!(scope.user).id, nil}
  rescue
    ArgumentError -> {"Private", Notebook.Spaces.private!(scope.user).id, nil}
  end

  defp updated(socket, page, message) do
    socket
    |> assign(page: page, page_title: page.title, form: to_form(Pages.change(page)))
    |> page_actions()
    |> put_flash(:info, message)
  end

  defp load_page(socket, %{"id" => id} = params) do
    scope = socket.assigns.current_scope
    page = Pages.get!(scope, id)

    socket =
      socket
      |> assign(
        page: page,
        page_title: page.title,
        can_edit?: Pages.allowed?(scope, :edit, page),
        can_share?: Notebook.Sharing.can_share?(scope, page),
        publishing?: false,
        in_space?: Notebook.Spaces.allowed?(scope, :read, page.space),
        sharing?: false,
        form: to_form(Pages.change(page)),
        # The page's room: its people and their pointers, listed and drawn
        # once for the page, whatever it is.
        grant: Issho.Live.grant(Notebook.Issho, user(socket), Notebook.Collaboration.room(page)),
        editing?: Map.has_key?(params, "edit"),
        mentionable: mentionable(page),
        asking: nil,
        agents: Notebook.Agents.list(scope)
      )
      |> assign_kind(page)
      |> join_room(page)
      |> suggestions()

    allow_upload(socket, :attachments,
      accept: ~w(.png .jpg .jpeg .gif .webp .pdf .mp4 .webm),
      max_file_size: 100_000_000,
      max_entries: 12,
      auto_upload: true,
      progress: &handle_progress/3
    )
  end

  defp load_page(socket, params) do
    scope = socket.assigns.current_scope

    assign(socket,
      pages: Pages.list(scope),
      places: places(scope),
      place: place_param(params, scope),
      page: nil,
      today: Koyomi.Rules.today(Page.review_rules()),
      form: to_form(Pages.change(%Page{})),
      grant: nil,
      issho: nil
    )
  end

  # The LiveView is in the page's room too, for its comments, and hears
  # the page's actions done there (an agent renamed it, gave it a due date).
  defp join_room(socket, page) do
    if connected?(socket) do
      room = Notebook.Collaboration.room(page)
      {:ok, _} = Issho.Live.join(Notebook.Issho, user(socket), room)
      Issho.Live.subscribe(room, :self, events: ["action.done"])
    end

    socket
  end

  # What an agent answers in the text (a stream at a place of its body,
  # for this person: Issho.Requests) shows in the editor, inline, to take
  # or leave (Kotoba.Issho.suggestions/4). Once for each page.
  defp suggestions(%{assigns: %{issho: [_ | _] = issho}} = socket) do
    socket
    |> Phoenix.LiveView.detach_hook(:kotoba_issho_suggestions, :handle_info)
    |> Phoenix.LiveView.detach_hook(:kotoba_issho_suggestions, :handle_event)
    |> Kotoba.Issho.suggestions(user(socket), %{"body-editor" => issho}, display: :inline)
  end

  defp suggestions(socket), do: socket

  # Whom a comment may mention, though they are not on the page: every
  # account, and every agent that may work, which finds it in its inbox.
  defp mentionable(page) do
    people = Enum.map(Notebook.Accounts.list_users(), &%{key: to_string(&1.id), name: &1.name})

    # No agent on a page off limits to agents: none would read what it says.
    agents =
      if Pages.closed_to_agents?(page),
        do: [],
        else:
          Enum.map(Notebook.Agents.active(), fn agent ->
            %{key: Notebook.Agents.key(agent), name: agent.name, kind: "agent"}
          end)

    people ++ agents
  end

  # What the page is: its shared text, its board, or its table, each a part
  # of the page's room.
  defp assign_kind(socket, %Page{kind: "board"} = page),
    do: assign(socket, issho: nil, graph: Notebook.Boards.graph(page))

  defp assign_kind(socket, %Page{kind: "table"} = page),
    do: assign(socket, issho: nil, grid: Notebook.Grids.rows(page))

  # A database: its collection, its views, the one shown, and its records.
  defp assign_kind(socket, %Page{kind: "database"} = page) do
    collection = Databases.collection(page)
    if connected?(socket), do: Box.subscribe(collection)

    socket
    |> assign(
      issho: nil,
      collection: collection,
      people: Databases.people(page),
      field_form: nil,
      day: nil,
      day_records: []
    )
    |> show_view(nil)
  end

  defp assign_kind(socket, page) do
    charts = Charts.embeddable(socket.assigns.current_scope, page)

    # A chart moves as its spec or its table's rows change.
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Notebook.PubSub, Charts.topic(page.id))
      Charts.watch_rows(for {_id, %{chart: chart}} <- charts, do: chart.source_id)
    end

    assign(socket,
      boards: embeddable(socket.assigns.current_scope, "board"),
      tables: embeddable(socket.assigns.current_scope, "table"),
      charts: charts,
      issho: [
        instance: Notebook.Issho,
        document: "#{Notebook.Collaboration.room(page)}/body",
        people: false,
        undo: :page
      ]
    )
  end

  # The boards and tables a text embeds, by their page's id as the document
  # keeps it: each page, and its graph or its grid.
  defp embeddable(scope, kind) do
    for page <- Pages.list(scope),
        page.kind == kind,
        into: %{},
        do: {to_string(page.id), embeddable_page(page)}
  end

  defp embeddable_page(%Page{kind: "board"} = page),
    do: %{page: page, graph: Notebook.Boards.graph(page)}

  defp embeddable_page(%Page{kind: "table"} = page),
    do: %{page: page, grid: Notebook.Grids.rows(page)}

  # A link to a board or a table of the Notebook, pasted or dropped in a
  # text, is the board or the table itself.
  defp resolve_embed(scope, url) do
    with %URI{host: host, path: "/pages/" <> id} <- URI.parse(url),
         true <- host in [nil, NotebookWeb.Endpoint.host()],
         {id, ""} <- Integer.parse(id),
         %Page{kind: kind} = page when kind in ["board", "table"] <- Pages.get(scope, id) do
      %{kind: kind, ref: to_string(page.id), title: page.title}
    else
      _other -> nil
    end
  end

  defp embedded(assigns, "board"), do: assigns.boards
  defp embedded(assigns, "table"), do: assigns.tables
  defp embedded(assigns, "chart"), do: assigns.charts
  defp embedded(_assigns, _kind), do: %{}

  # The person, as every part of the page knows them: the same key, name
  # and color in the text, the board, the table and the room's list.
  defp user(%{assigns: assigns}), do: user(assigns)

  defp user(%{current_scope: %{user: account, link_tokens: links}}) do
    person = %{
      id: to_string(account.id),
      name: account.name,
      color: Notebook.Accounts.User.color(account)
    }

    # The links they followed go with them, signed, to the page's room.
    if links == [], do: person, else: Issho.Identity.new(person, claims: %{links: links})
  end

  defp prompts(scope) do
    [
      {"@", :people, [search: &Notebook.People.search/1, label: "People", spaces: true]},
      {"#", :pages, [search: &Pages.mentions(scope, &1), label: "Pages", spaces: true]}
    ]
  end

  # A page's board, on its own page or embedded in a text (a Kotoba embed),
  # in the board's room either way.
  attr :id, :string, required: true
  attr :page, Page, required: true
  attr :graph, :any, required: true
  attr :user, :map, required: true
  attr :embedded, :boolean, default: false

  defp board(assigns) do
    ~H"""
    <.canvas
      id={@id}
      graph={@graph}
      issho={[instance: Notebook.Issho, document: Notebook.Collaboration.room(@page)]}
      user={@user}
      on_change={Notebook.Boards.on_change(@page.id)}
      new_node={&Notebook.Boards.new_node/2}
      background={:dots}
      grid={20}
      snap
      rules={[loops: false]}
      class="board-canvas"
      wheel={if @embedded, do: :scroll, else: :pan}
      refit={@embedded}
      minimap={not @embedded}
      label={"The board of " <> @page.title}
    >
      <:node :let={node} type="title">
        <div class="board-title">
          <strong>{node.data["text"]}</strong><span>{node.data["sub"]}</span>
        </div>
      </:node>
      <:node :let={node} type="card">
        <div class="board-card">
          <.handle kind={:both} side={:left} />
          <.handle kind={:both} side={:right} />
          <.handle kind={:both} side={:bottom} />
          <small>{node.data["kicker"]}</small>
          <p>{node.data["text"]}</p>
          <em :if={node.data["foot"]}>{node.data["foot"]}</em>
        </div>
      </:node>
      <:node :let={node} type="note" resizable>
        <div class="board-note" data-tone={node.data["tone"] || "ochre"}>
          <.handle kind={:both} side={:left} />
          <.handle kind={:both} side={:right} />
          {node.data["text"]}
        </div>
      </:node>
      <:node :let={node} type="page">
        <div class="board-page-card">
          <.handle kind={:both} side={:left} />
          <span class="eyebrow">{kind_name(node.data["kind"])} / {node.data["page"]}</span>
          <strong>{node.data["title"]}</strong>
          <.link navigate={~p"/pages/#{node.data["page"]}"}>Open ↗</.link>
        </div>
      </:node>
      <:node :let={node} type="frame" group resizable>
        <div class="board-frame-node">
          <span data-hakushi-drag>{node.data["title"]}</span>
        </div>
      </:node>
    </.canvas>
    """
  end

  # A board or a table in a text (a Kotoba embed): the page's own, live in
  # its room. The table is the table page's grid, under its name there: one
  # grid, wherever it is.
  attr :embed, :map, required: true
  attr :found, :map, default: nil, doc: "the page and its graph or grid, or nil"
  attr :user, :map, required: true
  attr :scope, :any, required: true

  defp embedded(%{found: nil} = assigns) do
    ~H"""
    <p class="embed-gone">{@embed.title}: this {@embed.kind} is gone.</p>
    """
  end

  defp embedded(%{embed: %{kind: "chart"}} = assigns) do
    ~H"""
    <.chart
      id={"chart-" <> @embed.id}
      spec={@found.chart.spec}
      data={@found.rows}
      issho={Charts.document(@found.chart)}
      height={if @embed.full, do: :fill, else: 300}
      class="embedded-chart"
    />
    """
  end

  defp embedded(%{embed: %{kind: "board"}} = assigns) do
    ~H"""
    <.canvas_embed
      title={@found.page.title}
      subtitle="Board"
      for={"board-" <> @embed.id}
      readonly={@embed.readonly}
      full={@embed.full}
      on_full={@embed.toggle_full}
    >
      <.board
        id={"board-" <> @embed.id}
        page={@found.page}
        graph={@found.graph}
        user={@user}
        embedded
      />
    </.canvas_embed>
    """
  end

  defp embedded(%{embed: %{kind: "table"}} = assigns) do
    ~H"""
    <.data_grid
      {@found.grid}
      id={"table-" <> @embed.id}
      issho={[
        instance: Notebook.Issho,
        document: Notebook.Collaboration.room(@found.page) <> "/rows",
        can: if(@embed.readonly, do: :read, else: :write)
      ]}
      user={@user}
      scope={@scope}
      label={"The table of " <> @found.page.title}
      height={if @embed.full, do: "100%", else: "auto"}
      max_height="24rem"
      wheel={if @embed.full, do: :grid, else: :page}
    />
    """
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :prompts, prompts(assigns.current_scope))

    ~H"""
    <.live_component
      :if={assigns[:publishing?] && assigns[:page]}
      module={NotebookWeb.PublishComponent}
      id="publish-dialog"
      resource={@page}
      scope={@current_scope}
    />
    <.live_component
      :if={assigns[:sharing?] && assigns[:page]}
      module={NotebookWeb.ShareComponent}
      id="share-dialog"
      resource={@page}
      space={@page.space}
      scope={@current_scope}
    />
    <.ask_dialog :if={assigns[:asking]} asking={@asking} agents={@agents} />
    <div class="notebook-shell notebook-with-sidebar">
      <.sidebar tree={@tree} chime={@chime} shared={@shared} current={current(assigns)} />
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
              <.command_button id="index-commands" class="button command-trigger" />
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
                  <span class="page-kicker">{kind_name(page.kind)} / {page.id}</span><h2>
                    {page.title}
                  </h2><p :if={not Map.has_key?(@snippets, page.id)}>
                    {excerpt(page)}
                  </p><p :if={Map.has_key?(@snippets, page.id)} class="page-snippet">
                    <%= for {text, matched?} <- @snippets[page.id] do %>
                      <mark :if={matched?}>{text}</mark><span :if={not matched?}>{text}</span>
                    <% end %>
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
            <.link navigate={~p"/"}>← Home</.link>
            <div class="page-nav-end">
              <.command_button id="page-commands" class="command-link" /><span>NEW PAGE</span>
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
            <label for="page_place" class="field-label">In</label>
            <select id="page_place" name="page[place]" class="page-place">
              <option
                :for={{label, space_id, folder_id} <- @places}
                value={"#{space_id}:#{folder_id}"}
                selected={{label, space_id, folder_id} == @place}
              >
                {label}
              </option>
            </select>
            <fieldset class="page-kinds">
              <legend class="field-label">A page of</legend>
              <label :for={{kind, name, hint} <- kinds()} class="page-kind">
                <input
                  type="radio"
                  name="page[kind]"
                  value={kind}
                  checked={to_string(@form[:kind].value || "text") == kind}
                />
                <span><strong>{name}</strong><small>{hint}</small></span>
              </label>
            </fieldset>
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
            <label
              :if={to_string(@form[:kind].value || "text") == "text"}
              class="field-label"
              for="new-body"
            >Body</label>
            <.kotoba
              :if={to_string(@form[:kind].value || "text") == "text"}
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

        <div
          :if={@live_action in [:show, :edit] and @page.kind == "board"}
          class="page-view page-space"
        >
          <.page_bar
            page={@page}
            grant={@grant}
            can_edit?={@can_edit?}
            can_share?={@can_share?}
            in_space?={@in_space?}
          />
          <div class="page-heading">
            <p class="eyebrow">Board · shared live</p>
            <h1>{@page.title}</h1>
            <p>{kind_hint(@page.kind)}</p>
          </div>
          <div
            id="board-frame"
            class="space-frame board-frame"
            data-issho-anchor="board"
            phx-hook=".Maximize"
            phx-mounted={JS.ignore_attributes(["data-maximized"])}
          >
            <div class="space-tools">
              <.canvas_item for="board" item="card" class="space-add">
                <.icon name="hero-rectangle-stack" class="size-4" /> Card
              </.canvas_item>
              <.canvas_item for="board" item="note" class="space-add">
                <.icon name="hero-pencil" class="size-4" /> Note
              </.canvas_item>
              <.canvas_item for="board" item="frame" class="space-add">
                <.icon name="hero-square-2-stack" class="size-4" /> Frame
              </.canvas_item>
              <span class="space-hint">Drag from a card's side to another to join them.</span>
              <.maximize_buttons />
            </div>
            <.board id="board" page={@page} graph={@graph} user={user(assigns)} />
          </div>
        </div>

        <div
          :if={@live_action in [:show, :edit] and @page.kind == "database"}
          class="page-view page-space"
        >
          <.page_bar
            page={@page}
            grant={@grant}
            can_edit?={@can_edit?}
            can_share?={@can_share?}
            in_space?={@in_space?}
          />
          <div class="page-heading">
            <p class="eyebrow">Database · shared live</p>
            <h1>{@page.title}</h1>
            <p>
              Records with the fields you give them, seen as a table, a board, a calendar or a chart.
            </p>
          </div>
          <div class="database-bar">
            <nav class="database-views" aria-label="Views">
              <button
                :for={view <- @views}
                id={"view-#{view.id}"}
                type="button"
                class={["database-view-tab", @view && view.id == @view.id && "is-current"]}
                phx-click="db_view"
                phx-value-id={view.id}
              >
                <.icon name={view_icon(view.type)} class="size-4" />{view.name}
              </button>
            </nav>
            <div :if={@can_edit?} class="database-actions">
              <details class="database-menu">
                <summary><.icon name="hero-plus" class="size-4" /> View</summary>
                <div class="database-menu-panel">
                  <button
                    :for={{type, name, icon} <- Databases.view_types()}
                    type="button"
                    phx-click="db_add_view"
                    phx-value-type={type}
                  >
                    <.icon name={icon} class="size-4" />{name}
                  </button>
                </div>
              </details>
              <button type="button" class="database-add" phx-click="db_add_record">
                <.icon name="hero-plus" class="size-4" /> Record
              </button>
              <button type="button" class="database-add" phx-click="db_new_field">
                <.icon name="hero-plus" class="size-4" /> Field
              </button>
            </div>
          </div>
          <.form
            :if={@field_form}
            for={@field_form}
            id="field-form"
            phx-submit="db_add_field"
            class="folder-form"
          >
            <input
              name="field[name]"
              placeholder="A field's name: Client, Price, Due…"
              maxlength="60"
              required
              autofocus
            />
            <select name="field[type]" aria-label="Type">
              <option :for={{type, name} <- Databases.field_types()} value={type}>{name}</option>
            </select>
            <button class="button button-primary" type="submit">Add field</button>
            <button class="copy-action" type="button" phx-click="db_cancel_field">Cancel</button>
          </.form>
          <div :if={@view} id="database-frame" class="space-frame database-frame">
            <Cardbox.Masu.table
              :if={@view.type == "table"}
              cardbox={Box}
              collection={@collection}
              view={@view}
              actor={@current_scope}
              people={@people}
              searchable
              height="32rem"
            />
            <Cardbox.Narabe.board
              :if={@view.type == "board"}
              id={"board-#{@view.id}"}
              collection={@collection}
              view={@view}
              records={@records}
              people={@people}
              on_move={@can_edit? && "db_move"}
              readonly={not @can_edit?}
            />
            <div :if={@view.type == "calendar"} class="database-calendar">
              <Cardbox.Koyomi.calendar id="db-calendar" view={@view} on_change="db_day" months={2} />
              <div class="database-day">
                <p :if={is_nil(@day)} class="field-hint">Pick a day for its records.</p>
                <p :if={@day} class="eyebrow">{Calendar.strftime(@day, "%A, %-d %B")}</p>
                <ul :if={@day} class="database-day-list">
                  <li :for={record <- @day_records}>{record_title(@collection, record)}</li>
                  <li :if={@day_records == []} class="field-hint">Nothing on this day.</li>
                </ul>
              </div>
            </div>
            <Cardbox.Fude.chart
              :if={@view.type == "chart"}
              id={"chart-#{@view.id}"}
              cardbox={Box}
              collection={@collection}
              view={@view}
              people={@people}
              me={Databases.me(@current_scope)}
              height={360}
            />
          </div>
        </div>

        <div
          :if={@live_action in [:show, :edit] and @page.kind == "table"}
          class="page-view page-space"
        >
          <.page_bar
            page={@page}
            grant={@grant}
            can_edit?={@can_edit?}
            can_share?={@can_share?}
            in_space?={@in_space?}
          />
          <div class="page-heading">
            <p class="eyebrow">{kind_name(@page.kind)} · shared live</p>
            <h1>{@page.title}</h1>
            <p>{kind_hint(@page.kind)}</p>
          </div>
          <div
            id="table-frame"
            class="space-frame table-frame"
            data-issho-anchor="table"
            phx-hook=".Maximize"
            phx-mounted={JS.ignore_attributes(["data-maximized"])}
          >
            <div class="space-tools">
              <span class="space-hint">Edit a cell as in a spreadsheet; paste rows from one.</span>
              <.maximize_buttons />
            </div>
            <.data_grid
              {@grid}
              issho={[
                instance: Notebook.Issho,
                document: Notebook.Collaboration.room(@page) <> "/rows",
                people: false
              ]}
              user={user(assigns)}
              scope={@current_scope}
              label={"The table of " <> @page.title}
              searchable
              height="32rem"
            />
          </div>
        </div>

        <div :if={@live_action in [:show, :edit] and @page.kind == "text"} class="page-view">
          <.page_bar
            page={@page}
            grant={@grant}
            can_edit?={@can_edit?}
            can_share?={@can_share?}
            in_space?={@in_space?}
          />
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
              :if={@can_edit?}
              class="button button-primary"
              navigate={~p"/pages/#{@page.id}/edit"}
              data-issho-anchor="edit-together"
              data-issho-follow
            >Edit together</.link>
            <button
              :for={{format, label} <- [markdown: "Copy Markdown", text: "Copy text"]}
              id={"copy-#{format}"}
              type="button"
              class="copy-action"
              phx-hook=".Copy"
              data-format={format}
              data-copy={copy_text(@page, format, @current_scope)}
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
          <article :if={@live_action == :show and not live_embeds?(@page)} class="page-body">
            <.kotoba_content content={@page.body} embed={Notebook.Embeds.renderer(@current_scope)} />
          </article>
          <%!-- A page with boards, tables or charts reads in a read-only editor, its embeds live. --%>
          <article
            :if={@live_action == :show and live_embeds?(@page)}
            class="page-body page-body-live"
          >
            <.kotoba
              field={@form[:body]}
              id="body-reader"
              label="Body"
              readonly
              show_toolbar={false}
              extensions={[~p"/assets/kotoba/extensions/callout.js"]}
              embeds
            />
            <.kotoba_embeds for="body-reader" readonly>
              <:embed :let={embed}>
                <.embedded
                  embed={embed}
                  found={embedded(assigns, embed.kind)[embed.ref]}
                  user={user(assigns)}
                  scope={@current_scope}
                />
              </:embed>
            </.kotoba_embeds>
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
              issho={@issho}
              user={user(assigns)}
              uploads={@uploads.attachments}
              prompts={@prompts}
              extensions={[~p"/assets/kotoba/extensions/callout.js"]}
              placeholder="Write something worth keeping…"
              assist={[ask: "Ask my agent…"]}
              embeds
            >
              <:selection>
                <.kotoba_selection_menu id="body-selection-menu" class="notebook-selection-menu">
                  <:button :if={@agents != []} command="assist" label="Ask my agent">
                    <.icon name="hero-sparkles" class="size-4" />
                  </:button>
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
          <.kotoba_embeds
            :if={@live_action == :edit}
            for="body-editor"
            label="Embed"
            icon="embed"
            picker_title="Embed a board, a table or a chart"
            resolve={&resolve_embed(@current_scope, &1)}
          >
            <:embed :let={embed}>
              <.embedded
                embed={embed}
                found={embedded(assigns, embed.kind)[embed.ref]}
                user={user(assigns)}
                scope={@current_scope}
              />
            </:embed>
            <:picker>
              <h3 :if={@boards != %{}}>Boards</h3>
              <.kotoba_embed_option
                :for={{id, board} <- @boards}
                phx-click="embed_page"
                phx-value-id={id}
                phx-value-kind="board"
                title={board.page.title}
                about="Notes and arrows, live in the text"
              />
              <h3 :if={@tables != %{}}>Tables</h3>
              <.kotoba_embed_option
                :for={{id, table} <- @tables}
                phx-click="embed_page"
                phx-value-id={id}
                phx-value-kind="table"
                title={table.page.title}
                about="Rows of tasks, live in the text"
              />
              <h3 :if={@tables != %{}}>Charts of a table</h3>
              <%= for {id, table} <- @tables, {preset, name, about} <- Charts.presets() do %>
                <.kotoba_embed_option
                  phx-click="embed_chart"
                  phx-value-source={id}
                  phx-value-preset={preset}
                  title={"#{name}: #{table.page.title}"}
                  about={about}
                />
              <% end %>
            </:picker>
          </.kotoba_embeds>
        </div>
      </main>
      <.comments_drawer
        :if={@live_action in [:show, :edit] and @page != nil}
        page={@page}
        mentionable={@mentionable}
      />
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

  # Maximize a board or a table to the window (Esc restores it), or to the
  # whole screen: the .Maximize hook of the frame they are in.
  # Whether a text has embeds, which its reader shows live.
  defp live_embeds?(%Page{
         kind: "text",
         body: %Kotoba.Content{doc: %{"root" => %{"children" => children}}}
       }),
       do: Enum.any?(children, &(&1["type"] == "embed"))

  defp live_embeds?(_page), do: false

  # What the sidebar marks as open.
  defp current(%{live_action: :index}), do: :home
  defp current(%{page: %Page{id: id}}), do: {:page, id}
  defp current(_assigns), do: nil

  # The database's views, and the one shown (its id, else the first), with
  # its records for a board.
  defp show_view(%{assigns: %{collection: collection}} = socket, id) do
    views = Databases.views(collection)
    view = Enum.find(views, &(to_string(&1.id) == to_string(id))) || List.first(views)

    records =
      if view && view.type == "board",
        do: Databases.records(socket.assigns.current_scope, collection, view),
        else: []

    assign(socket, views: views, view: view, records: records)
  end

  defp reload_database(%{assigns: %{collection: collection, view: view}} = socket) do
    socket
    |> assign(collection: Box.get_collection!(collection.id))
    |> show_view(view && view.id)
  end

  defp view_icon(type) do
    case List.keyfind(Databases.view_types(), type, 0) do
      {_type, _name, icon} -> icon
      nil -> "hero-squares-2x2"
    end
  end

  defp record_title(collection, record) do
    case Enum.find(collection.fields, &(&1.type == "text")) do
      nil -> "Untitled"
      field -> record.data[field.key] || "Untitled"
    end
  end

  defp maximize_buttons(assigns) do
    ~H"""
    <div class="space-size">
      <button
        type="button"
        class="space-button"
        data-space="maximize"
        title="Maximize (Esc to restore)"
      >
        <.icon name="hero-arrows-pointing-out" class="space-grow size-4" />
        <.icon name="hero-arrows-pointing-in" class="space-shrink size-4" />
        <span class="space-grow">Maximize</span><span class="space-shrink">Restore</span>
      </button>
      <button type="button" class="space-button" data-space="fullscreen" title="Full screen">
        <.icon name="hero-tv" class="size-4" /><span>Full screen</span>
      </button>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Maximize">
      // A board or a table of the page, maximized to the window or the
      // screen, and back; the canvas or the grid takes the new size.
      export default {
        mounted() {
          this.onClick = (event) => {
            const button = event.target.closest("[data-space]")
            if (!button || !this.el.contains(button)) return
            if (button.dataset.space === "maximize") this.toggle()
            else if (document.fullscreenElement) document.exitFullscreen()
            else (this.el.requestFullscreen?.() ?? Promise.reject()).catch(() => this.toggle(true))
          }
          this.onKey = (event) => {
            if (event.key === "Escape" && this.el.hasAttribute("data-maximized") && !document.fullscreenElement) this.toggle(false)
          }
          this.el.addEventListener("click", this.onClick)
          document.addEventListener("keydown", this.onKey)
          document.addEventListener("fullscreenchange", this.resized = () => window.dispatchEvent(new Event("resize")))
        },
        toggle(on = !this.el.hasAttribute("data-maximized")) {
          this.el.toggleAttribute("data-maximized", on)
          document.documentElement.classList.toggle("space-maximized", on)
          requestAnimationFrame(() => window.dispatchEvent(new Event("resize")))
        },
        destroyed() {
          document.removeEventListener("keydown", this.onKey)
          document.removeEventListener("fullscreenchange", this.resized)
          document.documentElement.classList.remove("space-maximized")
        }
      }
    </script>
    """
  end

  attr :page, Page, required: true
  attr :grant, :map, required: true
  attr :can_edit?, :boolean, default: false
  attr :can_share?, :boolean, default: false
  attr :in_space?, :boolean, default: true

  # The top of a page: where it is, who is on it, the commands; and
  # their pointers over the whole page.
  defp page_bar(assigns) do
    ~H"""
    <div class="page-nav">
      <nav :if={@in_space?} class="breadcrumb" aria-label="Where this page is">
        <.link navigate={~p"/spaces/#{@page.space_id}"}>{@page.space.name}</.link>
        <span :if={@page.folder} aria-hidden="true">/</span>
        <.link
          :if={@page.folder}
          navigate={~p"/spaces/#{@page.space_id}/folders/#{@page.folder_id}"}
        >
          {@page.folder.name}
        </.link>
      </nav>
      <nav :if={not @in_space?} class="breadcrumb" aria-label="Where this page is">
        <span><.icon name="hero-share" class="size-3.5" /> Shared with you</span>
      </nav>
      <div class="page-nav-end">
        <span
          :if={Pages.closed_to_agents?(@page)}
          class="agents-closed"
          id="agents-closed"
          title="No agent reads this page, finds it or joins it"
        >
          <.icon name="hero-no-symbol" class="size-3.5" /> No agents
        </span>
        <.people id="page-people" grant={@grant} label="On this page" />
        <button
          :if={@can_share?}
          id="publish-open"
          type="button"
          class={["command-link", @page.published_at && "is-published"]}
          phx-click="publish_open"
        >
          <.icon name="hero-globe-alt" class="size-4" />{if @page.published_at,
            do: "Published",
            else: "Publish"}
        </button>
        <button
          :if={@can_share?}
          id="share-open"
          type="button"
          class="command-link"
          phx-click="share_open"
        >
          <.icon name="hero-user-plus" class="size-4" />Share
        </button>
        <button
          id="comments-toggle"
          type="button"
          class="command-link comments-toggle"
          aria-controls="comments-drawer"
          phx-click={toggle_comments()}
        >
          <.icon name="hero-chat-bubble-left-right" class="size-4" />Comments
        </button>
        <.command_button id="page-commands" class="command-link" /><span>{kind_name(@page.kind)} / {@page.id}</span>
      </div>
    </div>
    <div :if={@page.archived_at} class="archived-banner" role="status">
      <.icon name="hero-archive-box" class="size-4" />
      <span>
        Archived on {Calendar.strftime(@page.archived_at, "%-d %B %Y")}. It is out of the sidebar and the lists.
      </span>
      <button :if={@can_edit?} type="button" phx-click="restore">Restore</button>
    </div>
    <.agents id="page-agents" grant={@grant} class="page-agents" />
    <.pointers id="page-pointers" grant={@grant} follow_agents="on_behalf" />
    """
  end

  attr :page, Page, required: true
  attr :mentionable, :list, required: true

  # The page's threads of comments, in a drawer at the side: on what one
  # selected in its text, board or table, or on the page. A thread's mark
  # on the page opens it.
  defp comments_drawer(assigns) do
    ~H"""
    <aside
      id="comments-drawer"
      class="comments-drawer"
      aria-label="Comments"
      phx-hook=".CommentsDrawer"
      phx-mounted={JS.ignore_attributes(["data-open"])}
    >
      <div class="comments-drawer-head">
        <span>Comments</span>
        <button
          type="button"
          class="command-link"
          phx-click={toggle_comments()}
          aria-label="Close comments"
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>
      <.comments
        id="page-comments"
        room={Notebook.Collaboration.room(@page)}
        mentionable={@mentionable}
      >
        <:place :let={%{place: place, default: default}}>{place_words(place, default)}</:place>
      </.comments>
    </aside>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".CommentsDrawer">
      // A thread's mark on the page opens the drawer at it; Escape closes it.
      export default {
        mounted() {
          this.open = (event) => {
            if (event.target.closest(".issho-comment-mark")) this.el.dataset.open = "true"
          }
          this.close = (event) => {
            if (event.key === "Escape" && this.el.dataset.open && !event.target.closest(".issho-mention-list")) {
              delete this.el.dataset.open
            }
          }
          document.addEventListener("click", this.open)
          this.el.addEventListener("keydown", this.close)
        },
        destroyed() {
          document.removeEventListener("click", this.open)
        }
      }
    </script>
    """
  end

  defp toggle_comments,
    do: JS.toggle_attribute({"data-open", "true"}, to: "#comments-drawer")

  # Where the person asked, in its words (Issho.Place's label): their
  # selection in the body (a Kotoba place: the answer replaces it), else its
  # block (the answer goes after it).
  defp asked_place(document, %{selection: %{"anchor" => _, "focus" => _} = selection, text: text}),
       do: %{"doc" => document, "at" => selection, "label" => text}

  defp asked_place(document, %{block: block, text: text}) when is_binary(block),
    do: %{"doc" => document, "at" => %{"node" => block}, "label" => text}

  defp asked_place(document, %{text: text}), do: %{"doc" => document, "label" => text}

  # The version of the body the person asked on (Issho.Version).
  defp version(document) do
    with {:ok, pid} <- Issho.Documents.open(Notebook.Issho, document),
         {:ok, snapshot} <- Issho.Authority.snapshot(pid) do
      Issho.Version.of(snapshot)
    else
      _ -> nil
    end
  end

  attr :asking, :map, required: true
  attr :agents, :list, required: true

  # What the person asks their agent, about what they selected: privately.
  defp ask_dialog(assigns) do
    ~H"""
    <div class="share-backdrop" phx-window-keydown="ask_close" phx-key="Escape">
      <section
        id="ask-dialog"
        class="share-dialog ask-dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby="ask-dialog-title"
        phx-click-away="ask_close"
      >
        <header class="share-head">
          <div>
            <p class="eyebrow">Only you and your agent see this</p>
            <h2 id="ask-dialog-title">Ask my agent</h2>
          </div>
          <button type="button" class="share-close" phx-click="ask_close" aria-label="Close">
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </header>
        <blockquote :if={@asking.text != ""} class="ask-selection">{@asking.text}</blockquote>
        <form id="ask-form" class="ask-form" phx-submit="ask">
          <label :if={length(@agents) > 1} class="field-label" for="ask-agent">Agent</label>
          <select :if={length(@agents) > 1} id="ask-agent" name="agent">
            <option :for={agent <- @agents} value={agent.id}>{agent.name}</option>
          </select>
          <input :if={length(@agents) == 1} type="hidden" name="agent" value={hd(@agents).id} />
          <label class="field-label" for="ask-question">
            What should {if length(@agents) == 1, do: hd(@agents).name, else: "it"} do?
          </label>
          <textarea
            id="ask-question"
            name="question"
            rows="3"
            maxlength="4000"
            required
            phx-mounted={JS.focus()}
            placeholder="Make this shorter"
          ></textarea>
          <p class="ask-hint">
            It answers here, in the text: you take its suggestion or leave it.
          </p>
          <button type="submit" class="button button-primary">Ask</button>
        </form>
      </section>
    </div>
    """
  end

  # Where a thread is, in the words of the page, and what, when its
  # component says it (Issho.Place's label): In the text: “Fold it”.
  defp place_words(nil, default), do: default

  defp place_words(%{"doc" => doc} = place, default) do
    where =
      cond do
        String.ends_with?(doc, "/body") -> "In the text"
        String.ends_with?(doc, "/rows") -> "In the table"
        String.starts_with?(doc, "page:") -> "On the board"
        true -> nil
      end

    case {where, place["label"]} do
      {nil, _label} -> default
      {where, label} when is_binary(label) and label != "" -> "#{where}: “#{label}”"
      {where, _label} -> where
    end
  end

  defp kinds do
    [
      {"text", "Text", "Words, written together"},
      {"board", "Board", "Notes and arrows, on a canvas"},
      {"table", "Table", "Rows of tasks, in a grid"},
      {"database", "Database", "Records with fields: a table, a board, a calendar"}
    ]
  end

  defp kind_name("board"), do: "BOARD"
  defp kind_name("table"), do: "TABLE"
  defp kind_name("database"), do: "DATABASE"
  defp kind_name(_text), do: "PAGE"

  defp kind_hint("board"),
    do: "Notes and the arrows between them. Everyone here moves them together, agents too."

  defp kind_hint("table"),
    do:
      "Rows everyone here edits together, agents too. Each change shows in the color of who made it."

  defp kind_hint(_text), do: nil

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
  defp agenda_days(scope, range) do
    for {day, items} <- Pages.agenda(Pages.list(scope), range), into: %{} do
      title = Enum.map_join(items, "; ", fn {kind, page} -> "#{@kinds[kind]}: #{page.title}" end)
      {day, [marks: Enum.map(items, fn {kind, _page} -> @tones[kind] end), title: title]}
    end
  end

  # The pages of the home page: the last changed, or those with the words
  # searched, the best first, each with what matched (Notebook.Search).
  defp list_pages(socket) do
    scope = socket.assigns.current_scope

    {pages, snippets} =
      case String.trim(socket.assigns.search) do
        "" ->
          {Pages.list(scope), %{}}

        search ->
          hits = Notebook.Search.search(scope, search, limit: 50)
          {Enum.map(hits, & &1.page), Map.new(hits, &{&1.page.id, &1.snippet})}
      end

    pages = if socket.assigns.day, do: Pages.on_day(pages, socket.assigns.day), else: pages
    assign(socket, pages: pages, snippets: snippets)
  end

  # The Markdown or the plain text of a page, for the copy buttons.
  defp copy_text(%{body: nil}, _format, _scope), do: ""
  defp copy_text(%{body: %Kotoba.Content{text: text}}, :text, _scope), do: text || ""

  defp copy_text(%{body: %Kotoba.Content{doc: doc}}, :markdown, scope) do
    case Kotoba.Document.parse(doc) do
      {:ok, parsed} ->
        Kotoba.Renderer.to_markdown(parsed, embed: Notebook.Embeds.renderer(scope))

      {:error, _messages} ->
        ""
    end
  end

  defp format_name("markdown"), do: "Markdown"
  defp format_name(_text), do: "Plain text"

  defp excerpt(%Page{kind: "board"}), do: "A board of notes and arrows, moved together."
  defp excerpt(%Page{kind: "table"}), do: "A table of tasks, edited together."

  defp excerpt(%Page{kind: "database"}),
    do: "Records and their fields, as a table, a board, a calendar or a chart."

  defp excerpt(%Page{body: body}), do: excerpt(body)
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
  # A chart of a table, made from one of its presets, in the text.
  def handle_event("embed_chart", %{"source" => source_id, "preset" => preset}, socket) do
    %{current_scope: scope, page: page} = socket.assigns
    %{page: source} = Map.fetch!(socket.assigns.tables, source_id)

    case Charts.create(scope, page, source, preset) do
      {:ok, chart} ->
        Charts.watch_rows([chart.source_id])

        {:noreply,
         socket
         |> assign(charts: Charts.embeddable(scope, page))
         |> Kotoba.Live.insert_embed("body-editor", "chart", to_string(chart.id),
           title: chart.spec["title"]
         )}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not make that chart.")}
    end
  end

  def handle_event("embed_page", %{"id" => id, "kind" => kind}, socket)
      when kind in ["board", "table"] do
    %{page: page} = Map.fetch!(embedded(socket.assigns, kind), id)
    {:noreply, Kotoba.Live.insert_embed(socket, "body-editor", kind, id, title: page.title)}
  end

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
    do: Koyomi.Live.handle_days(socket, params, &agenda_days(socket.assigns.current_scope, &1))

  # The review picker's free times; the page's own review is not taken.
  def handle_event("koyomi:days", %{"id" => "page_review_at_picker"} = params, socket) do
    page_id = socket.assigns.page && socket.assigns.page.id
    scope = socket.assigns.current_scope
    Koyomi.Live.handle_days(socket, params, &Pages.review_slots(scope, &1, page_id))
  end

  def handle_event("validate", %{"page" => params}, socket) do
    socket =
      if socket.assigns.page,
        do: Kotoba.Live.consume_uploads(socket, :attachments, "body-editor"),
        else: socket

    page = socket.assigns.page || %Page{}

    {:noreply,
     socket
     |> assign(form: to_form(Pages.change(page, params), action: :validate))
     |> keep_place(params)}
  end

  def handle_event("create", %{"page" => params}, socket) do
    case Pages.create(socket.assigns.current_scope, place_attrs(params)) do
      {:ok, %Page{kind: "text"} = page} ->
        {:noreply, push_navigate(socket, to: ~p"/pages/#{page.id}/edit")}

      {:ok, page} ->
        {:noreply, push_navigate(socket, to: ~p"/pages/#{page.id}")}

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
           Pages.update(
             socket.assigns.current_scope,
             socket.assigns.page,
             page_params(params, content)
           ) do
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

  def handle_event("restore", _params, socket), do: {:noreply, restore_page(socket)}

  # Ask my agent: the editor's Assist menu gives the selection and its
  # block; the person says what they want, and of which agent of theirs.
  def handle_event("kotoba:assist", %{"action" => "ask"} = params, socket) do
    case socket.assigns.agents do
      [] ->
        {:noreply, put_flash(socket, :error, "Connect an agent first, on the Agents page.")}

      _agents ->
        asking = %{
          text: params["text"] || "",
          block: get_in(params, ["place", "id"]),
          selection: get_in(params, ["place", "selection"])
        }

        {:noreply, assign(socket, asking: asking)}
    end
  end

  def handle_event("kotoba:assist", _params, socket), do: {:noreply, socket}

  def handle_event("ask_close", _params, socket), do: {:noreply, assign(socket, asking: nil)}

  def handle_event("ask", %{"question" => question, "agent" => agent_id}, socket) do
    %{asking: asking, agents: agents, page: page} = socket.assigns
    agent = Enum.find(agents, &(to_string(&1.id) == agent_id))
    room = Notebook.Collaboration.room(page)
    document = room <> "/body"

    result =
      agent &&
        Issho.Live.ask(room, question,
          agent: Notebook.Agents.key(agent),
          place: asked_place(document, asking),
          version: version(document)
        )

    case result do
      {:ok, _request} ->
        {:noreply,
         socket
         |> assign(asking: nil)
         |> put_flash(
           :info,
           "Asked #{agent.name}. Its answer comes here, for you to take or leave."
         )}

      _refused ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "#{(agent && agent.name) || "That agent"} may not be asked here."
         )}
    end
  end

  # The Share dialog (NotebookWeb.ShareComponent).
  def handle_event("share_open", _params, socket), do: {:noreply, assign(socket, sharing?: true)}

  def handle_event("share_close", _params, socket),
    do: {:noreply, assign(socket, sharing?: false)}

  # The Publish dialog (NotebookWeb.PublishComponent).
  def handle_event("publish_open", _params, socket),
    do: {:noreply, assign(socket, publishing?: true)}

  def handle_event("publish_close", _params, socket),
    do: {:noreply, assign(socket, publishing?: false)}

  # A database's views, fields, board moves and calendar days.
  def handle_event("db_view", %{"id" => id}, socket),
    do: {:noreply, socket |> assign(day: nil, day_records: []) |> show_view(id)}

  def handle_event("db_add_view", %{"type" => type}, socket) do
    case Databases.add_view(socket.assigns.current_scope, socket.assigns.collection, type) do
      {:ok, view} -> {:noreply, show_view(socket, view.id)}
      {:error, message} when is_binary(message) -> {:noreply, put_flash(socket, :error, message)}
      {:error, error} -> {:noreply, put_flash(socket, :error, Exception.message(error))}
    end
  end

  # A new, empty record: the action an agent's add_records runs.
  def handle_event("db_add_record", _params, socket) do
    args = %{page_id: socket.assigns.page.id, records: [%{}]}

    case Issho.Live.act(Notebook.Actions.AddRecords, args) do
      {:ok, _receipt} -> {:noreply, socket}
      {:error, reason} -> {:noreply, put_flash(socket, :error, Issho.Action.message(reason))}
    end
  end

  def handle_event("db_new_field", _params, socket),
    do:
      {:noreply,
       assign(socket, field_form: to_form(%{"name" => "", "type" => "text"}, as: :field))}

  def handle_event("db_cancel_field", _params, socket),
    do: {:noreply, assign(socket, field_form: nil)}

  def handle_event("db_add_field", %{"field" => params}, socket) do
    case Databases.add_field(socket.assigns.current_scope, socket.assigns.collection, params) do
      {:ok, _collection} -> {:noreply, socket |> assign(field_form: nil) |> reload_database()}
      {:error, error} -> {:noreply, put_flash(socket, :error, Exception.message(error))}
    end
  end

  def handle_event("db_move", params, socket) do
    %{collection: collection, view: view, current_scope: scope} = socket.assigns

    {:reply, reply, socket} =
      Cardbox.Narabe.handle_move(socket, params, Box, collection, view, actor: scope)

    {:reply, reply, show_view(socket, view.id)}
  end

  def handle_event("koyomi:days", %{"id" => "db-calendar"} = params, socket) do
    %{collection: collection, view: view, current_scope: scope} = socket.assigns
    Cardbox.Koyomi.handle_days(socket, params, Box, collection, view, me: Databases.me(scope))
  end

  def handle_event("db_day", %{"value" => value}, socket) do
    %{collection: collection, view: view} = socket.assigns

    case Date.from_iso8601(value || "") do
      {:ok, day} ->
        {:ok, records} = Cardbox.Koyomi.on_day(Box, collection, view, day)
        {:noreply, assign(socket, day: day, day_records: records)}

      _none ->
        {:noreply, assign(socket, day: nil, day_records: [])}
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
    do:
      {:noreply, Kotoba.Live.handle_prompt(socket, params, prompts(socket.assigns.current_scope))}

  # A chart's spec changed (a person or an agent), or a row of its table.
  @impl true
  def handle_info({event, _id}, %{assigns: %{page: %Page{kind: "text"} = page}} = socket)
      when event in [:chart_changed, :chart_rows] do
    {:noreply, assign(socket, charts: Charts.embeddable(socket.assigns.current_scope, page))}
  end

  # A change to the database, by anyone: its grid, its board, its calendar.
  def handle_info({:cardbox, event}, %{assigns: %{page: %Page{kind: "database"}}} = socket) do
    Cardbox.Masu.relay(event, "cardbox-#{socket.assigns.collection.id}")

    {:noreply,
     socket
     |> reload_database()
     |> Koyomi.Live.refresh_days("db-calendar")}
  end

  # Published, or taken back, from its dialog: the page's bar says so.
  def handle_info({:agents_changed, %Page{} = page}, socket),
    do: {:noreply, assign(socket, page: page, mentionable: mentionable(page))}

  def handle_info({:published, %Page{} = published}, %{assigns: %{page: page}} = socket),
    do:
      {:noreply,
       assign(socket,
         page: %{
           page
           | slug: published.slug,
             published_at: published.published_at,
             published_by_id: published.published_by_id
         }
       )}

  # An action done on the page, by anyone (this person's own included):
  # the page as it is now, when they read it (editing, their form stays
  # theirs). A database's records come by Cardbox's events.
  def handle_info(
        {Issho.Live, "event", _room, %Issho.Event{name: "action.done"}},
        %{assigns: %{live_action: :show}} = socket
      ) do
    case socket.assigns.page && Pages.get(socket.assigns.current_scope, socket.assigns.page.id) do
      %Page{} = page ->
        {:noreply,
         socket
         |> assign(page: page, page_title: page.title, form: to_form(Pages.change(page)))
         |> page_actions()}

      _gone ->
        {:noreply, socket}
    end
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp handle_progress(:attachments, entry, socket) do
    if entry.done?,
      do: {:noreply, Kotoba.Live.consume_uploads(socket, :attachments, "body-editor")},
      else: {:noreply, socket}
  end

  # The place picked in the new page's form stays picked as it validates.
  defp keep_place(socket, %{"place" => value}) do
    case Enum.find(socket.assigns[:places] || [], fn {_l, s, f} -> "#{s}:#{f}" == value end) do
      nil -> socket
      place -> assign(socket, place: place)
    end
  end

  defp keep_place(socket, _params), do: socket

  # The space and folder of the form's place ("space:folder").
  defp place_attrs(%{"place" => place} = params) do
    [space_id, folder_id] = String.split(place, ":")
    Map.merge(params, %{"space_id" => space_id, "folder_id" => folder_id})
  end

  defp place_attrs(params), do: params

  # The title and the dates come from the form; the body is the accepted
  # revision of the collaboration.
  defp page_params(params, content) do
    params
    |> Map.take(~w(title due_on covers review_at revisit))
    |> Map.put("body", content)
  end
end
