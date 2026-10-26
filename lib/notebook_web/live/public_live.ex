defmodule NotebookWeb.PublicLive do
  @moduledoc """
  A published page, a blog or a person's index, as anyone reads them
  (`Notebook.Publishing`), at their paths, wherever the notebook is read
  from (a site's proxy among them).

  A page reads as its editors see it, live: its text as it is saved, its
  charts as their tables change, its tables as their rows do; a board is
  drawn as it was when the page opened. What it embeds shows as its
  publisher may see it.
  """
  use NotebookWeb, :live_view

  alias Notebook.Accounts.Scope
  alias Notebook.Pages.Page
  alias Notebook.{Charts, Pages, Publishing}

  @impl true
  def mount(%{"path" => words}, session, socket) do
    socket = assign(socket, guest: Issho.Guests.new(session["guest"]), bots: [], asked: [])

    case Publishing.resolve(words) do
      {:page, page} -> {:ok, page(socket, page)}
      {:blog, folder, posts} -> {:ok, blog(socket, folder, posts)}
      {:person, user, published} -> {:ok, person(socket, user, published)}
      {:redirect, path} -> {:ok, redirect(socket, external: Publishing.config().url <> path)}
      _ -> raise NotebookWeb.NotFound
    end
  end

  ## A page

  defp page(socket, %Page{} = page) do
    # What it embeds, as its publisher may see it.
    scope = Scope.for_user(page.published_by)

    if connected?(socket) do
      Pages.subscribe(page.id)
      Phoenix.PubSub.subscribe(Notebook.PubSub, Charts.topic(page.id))
    end

    socket
    |> assign(
      kind: :page,
      page: page,
      scope: scope,
      page_title: page.title,
      description: Publishing.summary(page),
      canonical: Publishing.url(page),
      feed: page.folder && page.folder.published_at && Publishing.feed_url(page.folder),
      # The bots that answer visitors here (Notebook.Bots), and what was asked.
      bots: Notebook.Bots.public_for(page)
    )
    |> embeds()
  end

  # The page's text, its files at the notebook's address, and its embeds.
  defp embeds(%{assigns: %{page: page, scope: scope}} = socket) do
    page = %{page | body: Publishing.absolute_files(page.body)}
    charts = if page.kind == "text", do: Charts.embeddable(scope, page), else: %{}
    refs = embed_refs(page)

    pages =
      for {kind, ref} <- refs, kind in ["board", "table"], into: %{} do
        {ref, with_int(ref, &Pages.get(scope, &1))}
      end

    if connected?(socket) do
      Charts.watch_rows(for {_id, %{chart: chart}} <- charts, do: chart.source_id)
    end

    assign(socket,
      body: to_form(Pages.change(page))[:body],
      live_embeds?: refs != [],
      charts: charts,
      embedded: Map.reject(pages, fn {_ref, page} -> is_nil(page) end)
    )
  end

  defp embed_refs(%Page{
         kind: "text",
         body: %Kotoba.Content{doc: %{"root" => %{"children" => children}}}
       }) do
    for %{"type" => "embed"} = node <- children,
        kind = node["kind"] || get_in(node, ["data", "kind"]),
        ref = node["ref"] || get_in(node, ["data", "ref"]),
        do: {kind, to_string(ref)}
  end

  defp embed_refs(_page), do: []

  defp with_int(ref, fun) do
    case Integer.parse(ref) do
      {id, ""} -> fun.(id)
      _ -> nil
    end
  end

  ## A blog, and a person's index

  defp blog(socket, folder, posts) do
    assign(socket,
      kind: :blog,
      folder: folder,
      posts: posts,
      page_title: folder.name,
      description: "#{folder.name}, by #{folder.published_by && folder.published_by.name}",
      canonical: Publishing.url(folder),
      feed: Publishing.feed_url(folder)
    )
  end

  defp person(socket, user, %{pages: pages, blogs: blogs}) do
    assign(socket,
      kind: :person,
      person: user,
      pages: pages,
      blogs: blogs,
      page_title: user.name,
      description: "Pages by #{user.name}",
      canonical: Publishing.person_url(user),
      feed: nil
    )
  end

  ## Live

  @impl true
  def handle_info({:page_saved, id}, %{assigns: %{page: %{id: id}}} = socket) do
    case Publishing.resolve(
           String.split(URI.parse(Publishing.path(socket.assigns.page)).path, "/", trim: true)
         ) do
      {:page, page} ->
        {:noreply, socket |> assign(page: page, page_title: page.title) |> embeds()}

      _ ->
        {:noreply, push_navigate(socket, to: "/")}
    end
  end

  def handle_info({:chart_changed, _id}, socket), do: {:noreply, embeds(socket)}
  def handle_info({:chart_rows, _source}, socket), do: {:noreply, embeds(socket)}
  def handle_info({:watching, _ref}, socket), do: {:noreply, socket}
  # A bot's answer to what the visitor asked.
  def handle_info({:bot_answer, request, words}, socket) do
    asked =
      Enum.map(socket.assigns.asked, fn
        %{request: ^request} = asked -> %{asked | answer: words}
        asked -> asked
      end)

    {:noreply, assign(socket, asked: asked)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def handle_event("ask_bot", %{"bot" => id, "question" => question}, socket) do
    with %Notebook.Bots.Bot{} = bot <- Enum.find(socket.assigns.bots, &(to_string(&1.id) == id)),
         question when question != "" <- String.trim(question),
         {:ok, request} <-
           Notebook.Bots.ask_public(socket.assigns.page, bot, socket.assigns.guest, question) do
      asked = %{request: request, bot: bot.name, question: question, answer: nil}
      {:noreply, assign(socket, asked: socket.assigns.asked ++ [asked])}
    else
      {:error, :too_many} ->
        {:noreply,
         put_flash(socket, :error, "That is a lot of questions: ask again in a minute.")}

      _ ->
        {:noreply, socket}
    end
  end

  ## Rendering

  @impl true
  def render(assigns) do
    ~H"""
    <header class="public-bar">
      <a class="wordmark" href={home()}>{Publishing.config().name}<span class="wordmark-dot">.</span></a>
      <a :if={assigns[:feed]} class="public-feed" href={@feed} title="RSS">
        <.icon name="hero-rss" class="size-4" /> RSS
      </a>
    </header>
    <main class={["public-main", "public-#{@kind}"]}>
      <Layouts.flash_group flash={@flash} />
      <.public_page :if={@kind == :page} {assigns} />
      <.public_blog :if={@kind == :blog} {assigns} />
      <.public_person :if={@kind == :person} {assigns} />
    </main>
    <footer class="public-footer">
      <p>
        Published with <a href="https://github.com/hattoriai/notebook">Notebook</a>, pages you host yourself.
      </p>
    </footer>
    """
  end

  defp home do
    %{url: url, prefix: prefix} = Publishing.config()
    url <> prefix <> "/"
  end

  defp public_page(assigns) do
    ~H"""
    <article class="public-article">
      <p :if={@page.folder && @page.folder.published_at} class="eyebrow">
        <a href={Publishing.url(@page.folder)}>{@page.folder.name}</a>
      </p>
      <h1>{@page.title}</h1>
      <p class="public-byline">
        <a
          :if={@page.published_by && Publishing.config().paths == :people}
          href={Publishing.person_url(@page.published_by)}
        >
          {@page.published_by.name}
        </a>
        <span :if={@page.published_by && Publishing.config().paths == :solo}>{@page.published_by.name}</span>
        <span>·</span>
        <time datetime={DateTime.to_iso8601(@page.published_at)}>{Calendar.strftime(
          @page.published_at,
          "%-d %B %Y"
        )}</time>
      </p>

      <div :if={@page.kind == "text" and not @live_embeds?} class="page-body public-body-text">
        <.kotoba_content content={@body.value} embed={Notebook.Embeds.renderer(@scope)} />
      </div>
      <div
        :if={@page.kind == "text" and @live_embeds?}
        class="page-body page-body-live public-body-text"
      >
        <.kotoba
          field={@body}
          id="public-reader"
          label="Body"
          readonly
          show_toolbar={false}
          extensions={[static_url(NotebookWeb.Endpoint, ~p"/assets/kotoba/extensions/callout.js")]}
          embeds
        />
        <.kotoba_embeds for="public-reader" readonly>
          <:embed :let={embed}>
            <.public_embed embed={embed} charts={@charts} embedded={@embedded} />
          </:embed>
        </.kotoba_embeds>
      </div>
      <div :if={@page.kind == "board"} class="public-frame">
        <.canvas
          id="public-board"
          graph={Notebook.Boards.graph(@page)}
          readonly
          background={:dots}
          grid={20}
          class="board-canvas"
          label={"The board of " <> @page.title}
        />
      </div>
      <div :if={@page.kind == "table"} class="public-frame">
        <.data_grid
          {read_only(Notebook.Grids.rows(@page))}
          id="public-table"
          label={@page.title}
          max_height="40rem"
        />
      </div>

      <section
        :for={bot <- @bots}
        class="public-ask"
        id={"ask-#{bot.id}"}
        aria-label={"Ask #{bot.name}"}
      >
        <h2>Ask {bot.name}</h2>
        <ol class="public-asked">
          <li :for={asked <- @asked} :if={asked.bot == bot.name} id={"asked-" <> asked.request}>
            <p class="public-question">{asked.question}</p>
            <p :if={asked.answer} class="public-answer">{asked.answer}</p>
            <p :if={!asked.answer} class="public-answer is-waiting">{bot.name} is thinking…</p>
          </li>
        </ol>
        <form id={"ask-form-#{bot.id}"} phx-submit="ask_bot" class="public-ask-form">
          <input type="hidden" name="bot" value={bot.id} />
          <textarea
            name="question"
            rows="2"
            maxlength="2000"
            required
            placeholder={"A question about this page, for #{bot.name}"}
            aria-label={"Your question for #{bot.name}"}
          ></textarea>
          <button type="submit" class="button">Ask</button>
        </form>
        <p class="public-ask-note">
          {bot.name} is a bot: it reads this page and answers; it may be wrong.
        </p>
      </section>
    </article>
    """
  end

  attr :embed, :map, required: true
  attr :charts, :map, required: true
  attr :embedded, :map, required: true

  defp public_embed(%{embed: %{kind: "chart"}} = assigns) do
    ~H"""
    <%= case @charts[@embed.ref] do %>
      <% nil -> %>
        <p class="embed-gone">{@embed.title}</p>
      <% found -> %>
        <.chart
          id={"chart-" <> @embed.id}
          spec={found.chart.spec}
          data={found.rows}
          height={300}
          class="embedded-chart"
        />
    <% end %>
    """
  end

  defp public_embed(%{embed: %{kind: "table"}} = assigns) do
    ~H"""
    <%= case @embedded[@embed.ref] do %>
      <% nil -> %>
        <p class="embed-gone">{@embed.title}</p>
      <% page -> %>
        <.data_grid
          {read_only(Notebook.Grids.rows(page))}
          id={"table-" <> @embed.id}
          label={"The table of " <> page.title}
          max_height="24rem"
          wheel={:page}
        />
    <% end %>
    """
  end

  defp public_embed(%{embed: %{kind: "board"}} = assigns) do
    ~H"""
    <%= case @embedded[@embed.ref] do %>
      <% nil -> %>
        <p class="embed-gone">{@embed.title}</p>
      <% page -> %>
        <div class="public-embed-board">
          <.canvas
            id={"board-" <> @embed.id}
            graph={Notebook.Boards.graph(page)}
            readonly
            background={:dots}
            grid={20}
            class="board-canvas"
            wheel={:scroll}
            refit
            label={"The board of " <> page.title}
          />
        </div>
    <% end %>
    """
  end

  defp public_embed(assigns) do
    ~H"""
    <p class="embed-gone">{@embed.title}</p>
    """
  end

  # A table's grid, to read: it follows its rows, and changes nothing.
  defp read_only(grid), do: Keyword.drop(grid, [:changeset, :struct, :create_with, :deletable])

  defp public_blog(assigns) do
    ~H"""
    <section class="public-index">
      <p class="eyebrow">
        <a
          :if={@folder.published_by && Publishing.config().paths == :people}
          href={Publishing.person_url(@folder.published_by)}
        >
          {@folder.published_by.name}
        </a>
      </p>
      <h1>{@folder.name}</h1>
      <p :if={@posts == []} class="public-empty">Nothing published here yet.</p>
      <ol class="public-posts">
        <li :for={post <- @posts}>
          <time datetime={DateTime.to_iso8601(post.published_at)}>{Calendar.strftime(
            post.published_at,
            "%-d %B %Y"
          )}</time>
          <a href={Publishing.url(post)}><h2>{post.title}</h2></a>
          <p :if={Publishing.summary(post) != ""}>{Publishing.summary(post)}</p>
        </li>
      </ol>
    </section>
    """
  end

  defp public_person(assigns) do
    ~H"""
    <section class="public-index">
      <p class="eyebrow">Pages by</p>
      <h1>{@person.name}</h1>
      <p :if={@pages == [] and @blogs == []} class="public-empty">Nothing published yet.</p>
      <ol class="public-posts">
        <li :for={blog <- @blogs}>
          <span class="public-kind"><.icon name="hero-folder" class="size-3.5" /> Blog</span>
          <a href={Publishing.url(blog)}><h2>{blog.name}</h2></a>
        </li>
        <li :for={page <- @pages}>
          <time datetime={DateTime.to_iso8601(page.published_at)}>{Calendar.strftime(
            page.published_at,
            "%-d %B %Y"
          )}</time>
          <a href={Publishing.url(page)}><h2>{page.title}</h2></a>
          <p :if={Publishing.summary(page) != ""}>{Publishing.summary(page)}</p>
        </li>
      </ol>
    </section>
    """
  end
end
