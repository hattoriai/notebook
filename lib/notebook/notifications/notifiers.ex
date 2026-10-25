defmodule Notebook.Notifications.Mentioned do
  @moduledoc "Someone mentioned a person in a comment of a page."
  use Notebook.Notifier, category: :mentions

  alias Notebook.Notifier

  @impl true
  def recipients(_params), do: []

  @impl true
  def data(%{page: page, body: body, thread: thread}),
    do: %{
      "page_id" => page.id,
      "page" => page.title,
      "body" => Notifier.excerpt(body),
      "thread" => thread
    }

  @impl true
  def actor(%{by: by}), do: Notifier.actor(by)

  @impl true
  def feed(data, notification) do
    %{
      title: "#{Chime.actors(notification)} mentioned you in #{data["page"]}",
      body: data["body"],
      url: "/pages/#{data["page_id"]}",
      icon: "at"
    }
  end
end

defmodule Notebook.Notifications.Replied do
  @moduledoc "Someone replied in a thread of comments a person wrote in."
  use Notebook.Notifier, category: :replies, group_window: {1, :hour}

  alias Notebook.Notifier

  @impl true
  def recipients(_params), do: []

  @impl true
  def data(%{page: page, body: body, thread: thread}),
    do: %{
      "page_id" => page.id,
      "page" => page.title,
      "body" => Notifier.excerpt(body),
      "thread" => thread
    }

  @impl true
  def actor(%{by: by}), do: Notifier.actor(by)

  # The replies of one thread, within the hour, are one notification.
  @impl true
  def group(%{thread: thread}), do: thread && "thread:#{thread}"

  @impl true
  def feed(data, notification) do
    %{
      title: "#{Chime.actors(notification)} replied in #{data["page"]}",
      body: data["body"],
      url: "/pages/#{data["page_id"]}",
      icon: "reply"
    }
  end
end

defmodule Notebook.Notifications.Assigned do
  @moduledoc "Someone gave a person a record of a database page (a person field)."
  use Notebook.Notifier, category: :assignments

  @impl true
  def recipients(_params), do: []

  @impl true
  def data(%{page: page, record: record, title: title}),
    do: %{"page_id" => page.id, "page" => page.title, "record" => record, "title" => title}

  @impl true
  def actor(%{by: by}), do: Notebook.Notifier.actor(by)

  @impl true
  def group(%{record: record}), do: "record:#{record}"

  @impl true
  def feed(data, notification) do
    what = "#{data["title"] || "a record"} in #{data["page"]}"

    %{
      title:
        if(notification.actors in [nil, []],
          do: "You were given #{what}",
          else: "#{Chime.actors(notification)} gave you #{what}"
        ),
      url: "/pages/#{data["page_id"]}",
      icon: "user"
    }
  end
end

defmodule Notebook.Notifications.AddedToSpace do
  @moduledoc "Someone added a person to a team space."
  use Notebook.Notifier, category: :spaces

  @impl true
  def recipients(_params), do: []

  @impl true
  def data(%{space: space, role: role}),
    do: %{"space_id" => space.id, "space" => space.name, "role" => role}

  @impl true
  def actor(%{by: by}), do: Notebook.Notifier.actor(by)

  @impl true
  def feed(data, notification) do
    %{
      title: "#{Chime.actors(notification)} added you to #{data["space"]}",
      body: "You're #{article(data["role"])} #{data["role"]} there.",
      url: "/spaces/#{data["space_id"]}",
      icon: "space"
    }
  end

  defp article("admin"), do: "an"
  defp article("editor"), do: "an"
  defp article(_role), do: "a"
end

defmodule Notebook.Notifications.Shared do
  @moduledoc "Someone shared a page or a folder with a person."
  use Notebook.Notifier, category: :sharing

  @impl true
  def recipients(_params), do: []

  @impl true
  def data(%{resource: %Notebook.Pages.Page{} = page, role: role}),
    do: %{"page_id" => page.id, "page" => page.title, "role" => role}

  def data(%{resource: %Notebook.Spaces.Folder{} = folder, role: role}),
    do: %{
      "folder_id" => folder.id,
      "space_id" => folder.space_id,
      "folder" => folder.name,
      "role" => role
    }

  @impl true
  def actor(%{by: by}), do: Notebook.Notifier.actor(by)

  @impl true
  def feed(%{"page" => page} = data, notification) do
    %{
      title: "#{Chime.actors(notification)} shared #{page} with you",
      body: "You can #{can(data["role"])} it.",
      url: "/pages/#{data["page_id"]}",
      icon: "share"
    }
  end

  def feed(%{"folder" => folder} = data, notification) do
    %{
      title: "#{Chime.actors(notification)} shared the folder #{folder} with you",
      body: "You can #{can(data["role"])} its pages.",
      url: "/spaces/#{data["space_id"]}/folders/#{data["folder_id"]}",
      icon: "share"
    }
  end

  defp can("editor"), do: "edit"
  defp can("commenter"), do: "read and comment on"
  defp can(_viewer), do: "read"
end

defmodule Notebook.Notifications.Due do
  @moduledoc "A page of a person's is due today (at 09:00 of its due day)."
  use Notebook.Notifier, category: :dates

  @impl true
  def recipients(_params), do: []

  @impl true
  def data(%{page: page}),
    do: %{"page_id" => page.id, "page" => page.title, "due_on" => Date.to_iso8601(page.due_on)}

  @impl true
  def feed(data, _notification),
    do: %{
      title: "#{data["page"]} is due today",
      url: "/pages/#{data["page_id"]}",
      icon: "calendar"
    }
end

defmodule Notebook.Notifications.Review do
  @moduledoc "It is time to review a page of a person's (its review time)."
  use Notebook.Notifier, category: :dates

  @impl true
  def recipients(_params), do: []

  @impl true
  def data(%{page: page}), do: %{"page_id" => page.id, "page" => page.title}

  @impl true
  def feed(data, _notification),
    do: %{title: "Time to review #{data["page"]}", url: "/pages/#{data["page_id"]}", icon: "eye"}
end
