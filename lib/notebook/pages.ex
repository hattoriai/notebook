defmodule Notebook.Pages do
  @moduledoc """
  The notebook's pages. A page is in a space, and maybe in one of its
  folders; what a person may do with it is their role in its space
  (`Notebook.Permissions`), and an agent may do what its person may.
  Every function that reads or writes a page for someone takes their
  scope first.
  """
  import Ecto.Query
  alias Notebook.Accounts.Scope
  alias Notebook.Pages.Page
  alias Notebook.Permissions
  alias Notebook.Repo
  alias Notebook.Spaces
  alias Notebook.Spaces.{Folder, Space}

  @doc """
  The pages the scope may read, the last changed first.

    * `:search` - words of a title, a text or its records (`Notebook.Search`),
      the best first.
    * `:space_id` - only the pages of a space.
    * `:archived` - the archived pages instead of the others.
  """
  def list(scope, opts \\ []) do
    case String.trim(opts[:search] || "") do
      "" ->
        from(d in Page, order_by: [desc: d.updated_at], preload: [:author, :space])
        |> archived(opts[:archived] || false)
        |> in_space(opts[:space_id])
        |> Permissions.where_allowed(scope, :read)
        |> Repo.all()

      # Their words, the best first (Notebook.Search).
      search ->
        scope
        |> Notebook.Search.search(search, limit: 50, archived: opts[:archived] || false)
        |> Enum.map(& &1.page)
        |> Enum.filter(&(is_nil(opts[:space_id]) or &1.space_id == opts[:space_id]))
    end
  end

  defp archived(query, true), do: where(query, [p], not is_nil(p.archived_at))
  defp archived(query, false), do: where(query, [p], is_nil(p.archived_at))

  defp in_space(query, nil), do: query
  defp in_space(query, id), do: where(query, [p], p.space_id == ^id)

  @doc "A page the scope may read, or raises (a 404 for a page they may not read)."
  def get!(scope, id) do
    page = Page |> Repo.get!(id) |> Repo.preload([:author, :space, :folder])
    Permissions.authorize!(scope, :read, page)
    page
  end

  @doc "A page the scope may read, or nil."
  def get(scope, id) do
    with %Page{} = page <- Repo.get(Page, id),
         true <- Permissions.allowed?(scope, :read, page) do
      Repo.preload(page, [:author, :space, :folder])
    else
      _ -> nil
    end
  end

  @doc """
  A page by its id, for no one: for the app's own processes (the shared
  text's store, a room's board), after they checked who asks.
  """
  def fetch(id), do: Repo.get(Page, id)

  @doc "`:ok` when the scope may do what the permission says with the page, or `{:error, %Sekisho.Denied{}}`."
  def authorize(scope, permission, page), do: Permissions.authorize(scope, permission, page)

  @doc "Whether the scope may do what the permission says with the page."
  def allowed?(scope, permission, page), do: Permissions.allowed?(scope, permission, page)

  def change(page, attrs \\ %{}), do: Page.changeset(page, attrs)

  @doc """
  Makes a page with the scope's person as its author, in the space of
  `"space_id"` (General when not given) and the folder of `"folder_id"`.
  The space's editors may.
  """
  def create(%Scope{user: user} = scope, attrs) do
    attrs = Map.new(attrs, fn {key, value} -> {to_string(key), value} end)

    with {:ok, space} <- space_of(attrs["space_id"]),
         {:ok, folder_id} <- folder_in(attrs["folder_id"], space),
         :ok <- Permissions.authorize(scope, :edit, space),
         {:ok, page} <- insert(scope, user, space, folder_id, attrs) do
      Spaces.tree_changed()
      Notebook.Notifications.remind(page)
      # The bots that take new pages look at it, unless a bot made it.
      unless match?(%Scope{agent: "bot:" <> _}, scope), do: Notebook.Bots.page_created(page)
      {:ok, Repo.preload(page, [:author, :space, :folder])}
    end
  end

  # The page, and a database's collection with it, in one transaction.
  defp insert(scope, user, space, folder_id, attrs) do
    Repo.transact(fn ->
      with {:ok, page} <-
             %Page{author_id: user.id, space_id: space.id, folder_id: folder_id}
             |> Page.changeset(attrs)
             |> Narabe.Ecto.Mixed.put_position(Repo, Spaces.order(space))
             |> Repo.insert(),
           :ok <- with_collection(scope, page, attrs["fields"]) do
        {:ok, page}
      end
    end)
  end

  # A database's fields are its default ones, or those of "fields".
  defp with_collection(scope, %Page{kind: "database"} = page, fields) do
    created =
      if fields,
        do: Notebook.Databases.create(scope, page, fields),
        else: Notebook.Databases.create(scope, page)

    case created do
      {:ok, _collection} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp with_collection(_scope, _page, _fields), do: :ok

  defp space_of(id) when id in [nil, ""], do: {:ok, Spaces.general!()}

  defp space_of(id) do
    case Repo.get(Space, id) do
      %Space{} = space -> {:ok, space}
      nil -> {:error, :not_found}
    end
  end

  defp folder_in(id, _space) when id in [nil, ""], do: {:ok, nil}

  defp folder_in(id, %Space{id: space_id}) do
    case Repo.get(Folder, id) do
      %Folder{space_id: ^space_id, id: id} -> {:ok, id}
      _other -> {:error, :not_found}
    end
  end

  @doc "Changes a page: its space's editors may."
  def update(scope, page, attrs) do
    with :ok <- Permissions.authorize(scope, :edit, page),
         {:ok, updated} <- page |> Page.changeset(attrs) |> Repo.update() do
      if updated.title != page.title, do: Spaces.tree_changed()
      Notebook.Notifications.dates_changed(page, updated)
      saved({:ok, updated})
      {:ok, Repo.preload(updated, [:author, :space, :folder], force: true)}
    end
  end

  @doc "Publishes the accepted content of a page's shared text: its editors may."
  def publish(scope, page, content) do
    with :ok <- Permissions.authorize(scope, :edit, page) do
      page
      |> Ecto.Changeset.change(body: content)
      |> Repo.update()
      |> saved()
    end
  end

  @doc """
  Closes a page to agents, or opens it again: its editors may. Closed, an
  agent may not read it, find it, or join its room (`Notebook.Permissions`);
  one in its room is refused at its next step, and leaves.
  """
  def set_closed_to_agents(scope, page, closed?) when is_boolean(closed?) do
    with :ok <- Permissions.authorize(scope, :edit, page),
         {:ok, updated} <-
           page
           |> Ecto.Changeset.change()
           |> Ecto.Changeset.force_change(:closed_to_agents, closed?)
           |> Repo.update() do
      saved({:ok, updated})
      {:ok, Repo.preload(updated, [:author, :space, :folder], force: true)}
    end
  end

  @doc "Whether agents may not work on the page: it is closed to them, or its space is."
  def closed_to_agents?(%Page{closed_to_agents: true}), do: true
  def closed_to_agents?(%Page{} = page), do: Repo.preload(page, :space).space.closed_to_agents

  @doc "Subscribes the caller to `{:page_saved, id}`, sent when a page's content or details are saved."
  def subscribe(page_id), do: Phoenix.PubSub.subscribe(Notebook.PubSub, "page-saved:#{page_id}")

  defp saved({:ok, %Page{id: id}} = result) do
    Phoenix.PubSub.broadcast(Notebook.PubSub, "page-saved:#{id}", {:page_saved, id})
    result
  end

  defp saved(result), do: result

  @doc "Archives a page: it leaves the sidebar and the lists, and keeps its words."
  def archive(scope, page), do: set_archived(scope, page, DateTime.utc_now(:second))

  @doc "Brings an archived page back."
  def restore(scope, page), do: set_archived(scope, page, nil)

  defp set_archived(scope, page, at) do
    with :ok <- Permissions.authorize(scope, :edit, page),
         {:ok, updated} <- page |> Ecto.Changeset.change(archived_at: at) |> Repo.update() do
      Spaces.tree_changed()
      Notebook.Notifications.dates_changed(page, updated)
      {:ok, Repo.preload(updated, [:author, :space, :folder], force: true)}
    end
  end

  @doc """
  Moves a page to a space, and to one of its folders or none. The scope
  edits the page where it is, and the space it goes to.
  """
  def move(scope, page, space_id, folder_id \\ nil) do
    with {:ok, space} <- space_of(space_id),
         {:ok, folder_id} <- folder_in(folder_id, space),
         :ok <- Permissions.authorize(scope, :edit, page),
         :ok <- Permissions.authorize(scope, :edit, space),
         {:ok, page} <-
           page
           |> Ecto.Changeset.change(space_id: space.id, folder_id: folder_id, position: nil)
           |> Narabe.Ecto.Mixed.put_position(Repo, Spaces.order(space))
           |> Repo.update() do
      Spaces.tree_changed()
      {:ok, Repo.preload(page, [:author, :space, :folder], force: true)}
    end
  end

  @doc """
  The pages that have something on a day: due, covering it, reviewed or
  revisited then. `pages` are already loaded, as the index has them.
  """
  def on_day(pages, %Date{} = day), do: Enum.filter(pages, &(events(&1, day, day) != []))

  @doc """
  What each page has on the days of `range`, for the index calendar: a
  map from each day to a list of `{kind, page}`, where kind is `:due`,
  `:covers`, `:review` or `:revisit`.
  """
  def agenda(pages, %Date.Range{first: first, last: last}) do
    for page <- pages, {day, kind} <- events(page, first, last), reduce: %{} do
      acc -> Map.update(acc, day, [{kind, page}], &(&1 ++ [{kind, page}]))
    end
  end

  defp events(page, first, last) do
    within = &(Date.compare(&1, first) != :lt and Date.compare(&1, last) != :gt)

    due = if page.due_on && within.(page.due_on), do: [{page.due_on, :due}], else: []
    review_day = page.review_at && DateTime.to_date(local(page.review_at))
    review = if review_day && within.(review_day), do: [{review_day, :review}], else: []

    covers =
      case page.covers do
        %Date.Range{} = covers -> for day <- covers, within.(day), do: {day, :covers}
        nil -> []
      end

    due ++ review ++ covers ++ revisits(page, first, last)
  end

  defp revisits(%Page{revisit: nil}, _first, _last), do: []

  defp revisits(%Page{revisit: rule} = page, first, last) do
    rule
    |> Koyomi.Recurrence.between(revisit_start(page), first, last)
    |> Enum.map(&{&1, :revisit})
  end

  @doc "The first day of a page's revisits: its due day, else the day it was made."
  def revisit_start(%Page{due_on: %Date{} = due}), do: due
  def revisit_start(%Page{inserted_at: %DateTime{} = at}), do: DateTime.to_date(at)
  def revisit_start(%Page{}), do: Date.utc_today()

  @doc "The next revisit of a page from today, or nil."
  def next_revisit(%Page{revisit: nil}), do: nil

  def next_revisit(%Page{revisit: rule} = page) do
    today = Koyomi.Rules.today(Page.review_rules())

    rule
    |> Koyomi.Recurrence.occurrences(revisit_start(page))
    |> Enum.find(&(Date.compare(&1, today) != :lt))
  end

  @doc """
  The free review times of the days of `range`, for the review picker:
  every hour from 10:00 to 16:00 on weekdays, with the hours that another
  page's review takes disabled.
  """
  def review_slots(scope, %Date.Range{first: first, last: last} = range, except_id \\ nil) do
    zone = time_zone()
    starts = first |> DateTime.new!(~T[00:00:00], zone) |> DateTime.shift_zone!("Etc/UTC")

    ends =
      last |> Date.add(1) |> DateTime.new!(~T[00:00:00], zone) |> DateTime.shift_zone!("Etc/UTC")

    # Another page's review takes its hour, whoever may read it; only a
    # page the scope may read says which it is.
    reviews =
      from(p in Page, where: p.review_at >= ^starts and p.review_at < ^ends)
      |> exclude_page(except_id)

    readable =
      reviews
      |> Permissions.where_allowed(scope, :read)
      |> select([p], p.id)
      |> Repo.all()
      |> MapSet.new()

    taken =
      reviews
      |> select([p], {p.id, p.review_at, p.title})
      |> Repo.all()
      |> Map.new(fn {id, at, title} ->
        {DateTime.to_naive(local(at)), if(MapSet.member?(readable, id), do: title)}
      end)

    for day <- range, Date.day_of_week(day) in 1..5, into: %{} do
      slots =
        for hour <- 10..16 do
          time = Time.new!(hour, 0, 0)

          case Map.fetch(taken, NaiveDateTime.new!(day, time)) do
            {:ok, nil} -> %{time: time, label: "Taken", disabled: true}
            {:ok, title} -> %{time: time, label: "Taken: #{title}", disabled: true}
            :error -> %{time: time}
          end
        end

      free = Enum.count(slots, &(!Map.get(&1, :disabled)))
      {day, [slots: slots, title: "#{free} free #{if free == 1, do: "time", else: "times"}"]}
    end
  end

  defp exclude_page(query, nil), do: query
  defp exclude_page(query, id), do: where(query, [p], p.id != ^id)

  @doc "The time zone of the notebook's dates (`config :koyomi, :time_zone`)."
  def time_zone, do: Application.get_env(:koyomi, :time_zone, "Etc/UTC")

  @doc "An instant on the notebook's wall clock."
  def local(%DateTime{} = at), do: DateTime.shift_zone!(at, time_zone())

  def mentions(scope, query) do
    list(scope, search: query)
    |> Enum.take(20)
    |> Enum.map(&%{id: &1.id, label: &1.title, hint: "Page"})
  end
end
