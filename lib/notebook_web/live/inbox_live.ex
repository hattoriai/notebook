defmodule NotebookWeb.InboxLive do
  @moduledoc """
  The Inbox: a person's notifications (Chime), a page of them. What
  people said to them and gave them, and what is due, by day, the
  newest first: unread ones marked, each read as it is opened, and
  archived once dealt with. It follows the notifications live, as they
  come and as they are read in another tab or the bell.
  """
  use NotebookWeb, :live_view

  import NotebookWeb.Sidebar, only: [sidebar: 1]

  alias Notebook.Notifications

  @page 50

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    if connected?(socket), do: Notifications.watch(user)

    {:ok,
     socket
     |> assign(page_title: "Inbox", recipient: Notifications.id(user), limit: @page)
     |> assign(filter: :inbox)
     |> load()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filter =
      case params["show"] do
        "unread" -> :unread
        "archived" -> :archived
        _ -> :inbox
      end

    {:noreply, socket |> assign(filter: filter, limit: @page) |> load()}
  end

  # The notifications of the filter, rendered, and grouped by day.
  defp load(socket) do
    %{recipient: recipient, filter: filter, limit: limit} = socket.assigns
    notifications = Chime.feed(recipient, filter: filter, limit: limit + 1)
    {shown, more} = Enum.split(notifications, limit)

    items =
      for n <- shown do
        %{id: n.id, notification: n, feed: Chime.Feed.render(n)}
      end

    assign(socket, items: items, more: more != [], days: days(items))
  end

  defp days(items) do
    today = Date.utc_today()

    items
    |> Enum.chunk_by(&day(&1.notification.updated_at, today))
    |> Enum.map(fn [first | _] = items -> {day(first.notification.updated_at, today), items} end)
  end

  defp day(at, today) do
    date = at |> DateTime.shift_zone!(Notifications.time_zone()) |> DateTime.to_date()

    case Date.diff(today, date) do
      0 -> "Today"
      1 -> "Yesterday"
      n when n < 7 -> Calendar.strftime(date, "%A")
      _ -> Calendar.strftime(date, "%-d %B")
    end
  end

  @impl true
  def handle_info(:inbox_changed, socket), do: {:noreply, load(socket)}

  @impl true
  def handle_event("unread", %{"id" => id}, socket) do
    Chime.mark_unread(socket.assigns.recipient, [id])
    {:noreply, load(socket)}
  end

  def handle_event("read", %{"id" => id}, socket) do
    Chime.mark_read(socket.assigns.recipient, [id])
    {:noreply, load(socket)}
  end

  def handle_event("archive", %{"id" => id}, socket) do
    Chime.archive(socket.assigns.recipient, [id])
    {:noreply, load(socket)}
  end

  def handle_event("unarchive", %{"id" => id}, socket) do
    Chime.unarchive(socket.assigns.recipient, [id])
    {:noreply, load(socket)}
  end

  def handle_event("read_all", _params, socket) do
    Chime.mark_read(socket.assigns.recipient, :all)
    {:noreply, load(socket)}
  end

  def handle_event("more", _params, socket),
    do: {:noreply, socket |> update(:limit, &(&1 + @page)) |> load()}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="notebook-shell notebook-with-sidebar">
      <.sidebar tree={@tree} chime={@chime} shared={@shared} current={:inbox} />
      <main class="notebook-main">
        <div class="flash-area"><Layouts.flash_group flash={@flash} /></div>
        <div class="inbox-view">
          <div class="page-heading">
            <p class="eyebrow"><.icon name="hero-inbox" class="size-3.5" /> For you</p>
            <h1>Inbox</h1>
            <p>
              What people said to you and gave you, and what's due. Archive what you've dealt with.
            </p>
          </div>

          <div class="inbox-bar">
            <nav class="inbox-filters" aria-label="Show">
              <.link patch={~p"/inbox"} class={@filter == :inbox && "is-current"}>All</.link>
              <.link patch={~p"/inbox?show=unread"} class={@filter == :unread && "is-current"}>
                Unread <span :if={@chime.unread > 0} class="inbox-filter-count">{@chime.unread}</span>
              </.link>
              <.link patch={~p"/inbox?show=archived"} class={@filter == :archived && "is-current"}>
                Archived
              </.link>
            </nav>
            <button :if={@chime.unread > 0} type="button" class="inbox-read-all" phx-click="read_all">
              <.icon name="hero-check" class="size-4" /> Mark all as read
            </button>
          </div>

          <div :if={@items == []} class="inbox-empty">
            <.icon name="hero-inbox" class="size-6" />
            <p>{empty(@filter)}</p>
          </div>

          <section :for={{day, items} <- @days} class="inbox-day">
            <h2>{day}</h2>
            <ul class="inbox-list">
              <li
                :for={item <- items}
                id={"inbox-#{item.id}"}
                class={["inbox-item", is_nil(item.notification.read_at) && "is-unread"]}
              >
                <span class={["inbox-avatar", actor(item) == nil && "is-reminder"]} aria-hidden="true">
                  <%= if name = actor(item) do %>
                    {NotebookWeb.Layouts.initials(name)}
                  <% else %>
                    <.icon name={kind_icon(item.feed[:icon])} class="size-4" />
                  <% end %>
                </span>
                <button
                  type="button"
                  class="inbox-open"
                  phx-click="chime:visit"
                  phx-value-id={item.id}
                >
                  <span class="inbox-title">{item.feed.title}</span>
                  <span :if={item.feed[:body]} class="inbox-body">{item.feed[:body]}</span>
                  <time datetime={DateTime.to_iso8601(item.notification.updated_at)}>
                    {Calendar.strftime(
                      DateTime.shift_zone!(item.notification.updated_at, Notifications.time_zone()),
                      "%H:%M"
                    )}
                  </time>
                </button>
                <div class="inbox-actions">
                  <button
                    :if={is_nil(item.notification.read_at)}
                    type="button"
                    phx-click="read"
                    phx-value-id={item.id}
                    title="Mark as read"
                    aria-label="Mark as read"
                  >
                    <.icon name="hero-check" class="size-4" />
                  </button>
                  <button
                    :if={item.notification.read_at}
                    type="button"
                    phx-click="unread"
                    phx-value-id={item.id}
                    title="Mark as unread"
                    aria-label="Mark as unread"
                  >
                    <.icon name="hero-envelope" class="size-4" />
                  </button>
                  <button
                    :if={is_nil(item.notification.archived_at)}
                    type="button"
                    phx-click="archive"
                    phx-value-id={item.id}
                    title="Archive"
                    aria-label="Archive"
                  >
                    <.icon name="hero-archive-box-arrow-down" class="size-4" />
                  </button>
                  <button
                    :if={item.notification.archived_at}
                    type="button"
                    phx-click="unarchive"
                    phx-value-id={item.id}
                    title="Back to the Inbox"
                    aria-label="Back to the Inbox"
                  >
                    <.icon name="hero-arrow-uturn-left" class="size-4" />
                  </button>
                </div>
              </li>
            </ul>
          </section>

          <button :if={@more} type="button" class="inbox-more" phx-click="more">Show more</button>
        </div>
      </main>
    </div>
    """
  end

  # Who did it (the latest of them), or nil for a reminder.
  defp actor(%{notification: %{actors: [actor | _]}}), do: actor["name"]
  defp actor(_item), do: nil

  defp kind_icon("calendar"), do: "hero-calendar-days"
  defp kind_icon("eye"), do: "hero-eye"
  defp kind_icon("space"), do: "hero-user-group"
  defp kind_icon(_icon), do: "hero-bell"

  defp empty(:unread), do: "Nothing unread. You're all caught up."
  defp empty(:archived), do: "Nothing archived yet."

  defp empty(:inbox),
    do:
      "Nothing here yet. When someone mentions you, replies to you or gives you something, it's here."
end
