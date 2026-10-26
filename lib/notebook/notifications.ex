defmodule Notebook.Notifications do
  @moduledoc """
  What the Notebook tells people (Chime): someone mentioned them in a
  comment, or replied in a thread they are in; gave them a record of a
  database; added them to a space; a page of theirs is due today, or it
  is time to review it. Each one is in the person's Inbox at once (the
  sidebar's), and in an email ten minutes later if they have not read it
  by then. People choose what they hear of, and how, in their settings.

  The comments are Issho's and the records Cardbox's: the Notebook hears
  of them by their `:telemetry` events (`[:issho, :event]`,
  `[:cardbox, :change]`), whoever made them: a person on a page, or an
  agent over MCP. Nobody hears of what they did themselves, and nobody
  hears of a page they may not read (`Notebook.Notifier`).
  """
  alias Notebook.Accounts.{Scope, User}
  alias Notebook.Notifications, as: N
  alias Notebook.Pages.Page
  alias Notebook.{Pages, Repo}

  @categories [
    mentions: [label: "Mentions", description: "Someone mentions you in a comment."],
    replies: [label: "Replies", description: "Someone replies in a thread you are in."],
    assignments: [
      label: "Assigned to you",
      description: "Someone gives you a record of a database."
    ],
    spaces: [label: "Spaces", description: "Someone adds you to a space."],
    sharing: [
      label: "Shared with you",
      description: "Someone shares a page or a folder with you."
    ],
    dates: [
      label: "Due dates and reviews",
      description:
        "A page of yours is due today, a record of yours has its day, or it is time to review a page."
    ]
  ]

  @doc "Chime's options, for the application's supervisor."
  def config do
    [
      repo: Repo,
      pubsub: Notebook.PubSub,
      resolver: Notebook.Notifications.Resolver,
      mailer: Notebook.Mailer,
      email_from: Application.fetch_env!(:notebook, :email_from),
      secret_key_base: Application.fetch_env!(:notebook, NotebookWeb.Endpoint)[:secret_key_base],
      url: url(),
      mail_url: url() <> "/notifications/mail",
      categories: @categories,
      scheduler: Application.get_env(:notebook, :chime_scheduler, true)
    ]
  end

  @doc "The Notebook's address, from the endpoint's config: the links of the emails."
  def url do
    config = Application.get_env(:notebook, NotebookWeb.Endpoint, [])
    url = Keyword.get(config, :url, [])
    scheme = url[:scheme] || "http"
    port = url[:port] || get_in(config, [:http, :port]) || 4000
    default? = {scheme, port} in [{"http", 80}, {"https", 443}]
    "#{scheme}://#{url[:host] || "localhost"}#{if default?, do: "", else: ":#{port}"}"
  end

  @doc "The time zone of the notebook's days: when a page falls due."
  def time_zone, do: Application.get_env(:koyomi, :time_zone, "Etc/UTC")

  @doc "A person's id in the notifications: `user:<id>`."
  def id(%User{id: id}), do: "user:#{id}"

  @doc "The account of an id of the notifications, or nil."
  # A bot's account hears of nothing: what concerns the bot is in its inbox.
  def user("user:" <> id) do
    case Integer.parse(id) do
      {id, ""} -> Repo.get_by(User, id: id, bot: false)
      _ -> nil
    end
  end

  def user(_id), do: nil

  @doc "Whether a person may read a page, now: no one hears of a page they may not read."
  def may_read?(%User{} = user, page_id) do
    case Repo.get(Page, page_id) do
      %Page{archived_at: nil} = page -> Pages.allowed?(Scope.for_user(user), :read, page)
      _ -> false
    end
  end

  def may_read?(_nobody, _page_id), do: false

  @doc """
  Watches a person's notifications for the calling LiveView: it gets
  `:inbox_changed` when one comes, or is read or archived anywhere.
  `Chime.Live` takes Chime's messages, so a process linked to the
  LiveView listens for them.
  """
  def watch(%User{} = user) do
    me = self()
    ref = make_ref()

    spawn_link(fn ->
      Chime.subscribe(id(user))
      send(me, {:watching, ref})
      relay(me)
    end)

    # Back once it listens, so that no change after this call is missed.
    receive do
      {:watching, ^ref} -> :ok
    end
  end

  defp relay(to) do
    receive do
      _news ->
        send(to, :inbox_changed)
        relay(to)
    end
  end

  ## Hearing of Issho's comments and Cardbox's records

  @doc "Attaches the handlers of Issho's and Cardbox's events (at start)."
  def attach do
    :telemetry.attach_many(
      "notebook-notifications",
      [[:issho, :event], [:cardbox, :change]],
      &__MODULE__.handle_event/4,
      nil
    )
  end

  @doc false
  def handle_event(
        [:issho, :event],
        _measures,
        %{event: %Issho.Event{name: "comment.created"} = event},
        _
      ),
      do: run(fn -> comment(event) end)

  def handle_event(
        [:cardbox, :change],
        _measures,
        %{event: %Cardbox.Event{type: type} = event},
        _
      )
      when type in [:record_inserted, :record_updated],
      do:
        run(fn ->
          record(event)
          record_dates(event)
        end)

  def handle_event(
        [:cardbox, :change],
        _measures,
        %{event: %Cardbox.Event{type: :record_deleted, record: record}},
        _
      ),
      do: run(fn -> cancel_record_reminders(record.id) end)

  def handle_event(_name, _measures, _meta, _config), do: :ok

  # Away from the process of the change (a room's, whose comments a reply
  # reads; a LiveView's; a grid's), one after the other: SQLite takes one
  # writer at a time, and the notifications keep the order of the changes.
  defp run(fun), do: Notebook.Notifications.Queue.run(fun)

  @doc "Waits until what notifies of the changes made so far is done: for the seeds and the tests."
  def settle, do: Notebook.Notifications.Queue.settle()

  # A comment in a page's room: the people it mentions hear of it, and, of
  # a reply, the others who wrote in the thread.
  defp comment(%Issho.Event{room: room, by: by, data: data}) do
    with {:ok, page_id} <- page_of(room),
         %Page{} = page <- Repo.get(Page, page_id) do
      author = by && by.key
      mentioned = users(data[:mentions] || [], author)
      params = %{page: page, by: by, body: data[:body], thread: data[:thread]}

      for user <- mentioned, do: Chime.notify(N.Mentioned, params, to: user)

      if data[:reply] do
        case in_thread(room, data[:thread], [author | Enum.map(mentioned, &to_string(&1.id))]) do
          [] -> :ok
          people -> Chime.notify(N.Replied, params, to: people)
        end
      end
    end
  end

  defp page_of(room) do
    case Notebook.Collaboration.page_id(room) do
      id when is_integer(id) -> {:ok, id}
      _ -> :none
    end
  rescue
    _ -> :none
  end

  # The accounts of keys of Issho (a person's is their id), but one.
  defp users(keys, except) do
    ids =
      for key <- keys,
          key != except,
          {id, ""} <- [Integer.parse(to_string(key))],
          uniq: true,
          do: id

    if ids == [], do: [], else: Repo.all(from_ids(ids))
  end

  defp from_ids(ids) do
    import Ecto.Query
    from(u in User, where: u.id in ^ids and not u.bot)
  end

  # The people who wrote in a thread, but those already told.
  defp in_thread(room, thread_id, except) do
    case Issho.Comments.threads(Notebook.Issho, room) do
      {:ok, threads} ->
        threads
        |> Enum.find(&(&1["id"] == thread_id))
        |> case do
          nil -> []
          thread -> for(c <- thread["comments"] || [], do: get_in(c, ["author", "key"]))
        end
        |> users(nil)
        |> Enum.reject(&(to_string(&1.id) in except))

      _ ->
        []
    end
  end

  # A record of a database page given to people (its person fields): each
  # person in a field that changed, but the one who changed it.
  defp record(%Cardbox.Event{record: record, actor: actor} = event) do
    collection = Notebook.Cardbox.get_collection(event.collection_id)

    with %{owner_type: "page", owner_id: page_id} <- collection,
         %Page{} = page <- Repo.get(Page, page_id) do
      changed = if event.type == :record_inserted, do: :all, else: event.changed

      people =
        for field <- collection.fields,
            field.type == "person",
            changed == :all or field.key in changed,
            id <- List.wrap(Map.get(record.data, field.key)),
            id != actor,
            user = user(id),
            uniq: true,
            do: user

      title = Cardbox.Records.titles(Notebook.Cardbox, collection.id, [record.id])[record.id]
      by = actor && user(actor)

      for user <- people do
        Chime.notify(N.Assigned, %{page: page, record: record.id, title: title, by: by}, to: user)
      end
    end
  end

  ## Spaces and dates

  @doc "Tells a person a page or a folder was shared with them, as a role, by whom."
  def shared(resource, %User{} = user, role, %User{} = by),
    do: Chime.notify(N.Shared, %{resource: resource, role: role, by: by}, to: user)

  @doc "Tells a person they were added to a space, by whom."
  def added_to_space(space, %User{} = user, role, %User{} = by),
    do: Chime.notify(N.AddedToSpace, %{space: space, role: role, by: by}, to: user)

  @doc """
  After a page changed: its reminders follow its due day and its review
  time. The old ones are cancelled, and new ones wait for their time, for
  the page's author: at 09:00 of the due day, and at the review's time.
  """
  def dates_changed(%Page{} = before, %Page{} = page) do
    if before.due_on != page.due_on or before.review_at != page.review_at or
         before.archived_at != page.archived_at do
      cancel_reminders(page)
      remind(page)
    end

    :ok
  end

  @doc "The reminders of a page: its due day and its review time, still ahead."
  def remind(%Page{archived_at: nil, author_id: author_id} = page) when not is_nil(author_id) do
    author = Repo.get(User, author_id)
    now = DateTime.utc_now()

    if page.due_on do
      at =
        page.due_on |> DateTime.new!(~T[09:00:00], time_zone()) |> DateTime.shift_zone!("Etc/UTC")

      if Date.compare(page.due_on, DateTime.to_date(DateTime.shift_zone!(now, time_zone()))) !=
           :lt,
         do:
           Chime.notify(N.Due, %{page: page},
             to: author,
             at: later(at, now),
             key: key(page, :due)
           )
    end

    if page.review_at && DateTime.compare(page.review_at, now) == :gt,
      do:
        Chime.notify(N.Review, %{page: page},
          to: author,
          at: page.review_at,
          key: key(page, :review)
        )

    :ok
  end

  def remind(_page), do: :ok

  defp later(at, now),
    do: if(DateTime.compare(at, now) == :gt, do: at, else: DateTime.add(now, 1))

  # The reminders of a page that still wait for their time.
  defp cancel_reminders(%Page{id: id}) do
    import Ecto.Query

    for prefix <- ["due:page:#{id}:", "review:page:#{id}:"],
        event <-
          Repo.all(
            from e in Chime.Event,
              where: like(e.key, ^(prefix <> "%")) and e.status == "scheduled"
          ),
        do: Chime.cancel(event)
  end

  ## Records' days

  # A record's days (its date fields) remind its people (its person
  # fields, else whoever made it), at 09:00 of the day, or at the time of
  # a date with one, while the record is not done. Each change of a day,
  # of who it is for, or of being done sets them again.
  defp record_dates(%Cardbox.Event{record: record} = event) do
    collection = Notebook.Cardbox.get_collection(event.collection_id)

    with %{owner_type: "page", owner_id: page_id} <- collection,
         %Page{archived_at: nil} = page <- Repo.get(Page, page_id),
         true <- event.type == :record_inserted or reminds?(collection, event.changed) do
      cancel_record_reminders(record.id)
      unless done?(collection, record), do: remind_record(page, collection, record)
    end

    :ok
  end

  # Whether a change touches what a record's reminders depend on.
  defp reminds?(collection, changed) do
    Enum.any?(collection.fields, fn field ->
      field.key in changed and field.type in ~w(date person status checkbox)
    end)
  end

  # Done: its repeat's done field says so, else its first status is of the
  # done group.
  defp done?(collection, record) do
    repeat = Enum.find(collection.fields, &(&1.type == "repeat"))

    field =
      (repeat && Cardbox.Collection.field(collection, repeat.options["done"])) ||
        Enum.find(collection.fields, &(&1.type == "status"))

    field != nil and Notebook.Cardbox.Repeat.done?(field, record.data)
  end

  defp remind_record(page, collection, record) do
    people = record_people(collection, record)
    title = Cardbox.Records.titles(Notebook.Cardbox, collection.id, [record.id])[record.id]
    now = DateTime.utc_now()
    today = now |> DateTime.shift_zone!(time_zone()) |> DateTime.to_date()

    for %{type: "date"} = field <- collection.fields,
        value = Cardbox.Record.value(record, field),
        at = record_at(value),
        on_or_after?(value, today, now),
        people != [] do
      Chime.notify(
        N.RecordDue,
        %{page: page, record: record.id, title: title, field: field.name, on: value},
        to: people,
        at: later(at, now),
        key: "due:record:#{record.id}:#{field.key}:#{System.os_time(:microsecond)}"
      )
    end
  end

  defp record_at(%Date{} = day),
    do: day |> DateTime.new!(~T[09:00:00], time_zone()) |> DateTime.shift_zone!("Etc/UTC")

  defp record_at(%DateTime{} = at), do: at

  defp on_or_after?(%Date{} = day, today, _now), do: Date.compare(day, today) != :lt
  defp on_or_after?(%DateTime{} = at, _today, now), do: DateTime.compare(at, now) != :lt

  # Its person fields' people, else the person who made it.
  defp record_people(collection, record) do
    ids =
      for field <- collection.fields,
          field.type == "person",
          id <- List.wrap(Map.get(record.data, field.key)),
          do: id

    ids = if ids == [], do: List.wrap(record.created_by), else: ids
    for id <- Enum.uniq(ids), user = user(id), do: user
  end

  defp cancel_record_reminders(record_id) do
    import Ecto.Query

    prefix = "due:record:#{record_id}:"

    for event <-
          Repo.all(
            from e in Chime.Event,
              where: like(e.key, ^(prefix <> "%")) and e.status == "scheduled"
          ),
        do: Chime.cancel(event)

    :ok
  end

  # A reminder's key, of its page and its time; each one set is a new one,
  # so that a day set again after a change is reminded of again.
  defp key(%Page{id: id}, kind), do: "#{kind}:page:#{id}:#{System.os_time(:microsecond)}"
end
