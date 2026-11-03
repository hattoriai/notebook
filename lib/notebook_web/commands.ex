defmodule NotebookWeb.Commands do
  @moduledoc """
  The actions of the command palette (⌘K), for each LiveView of the
  live_sessions that mount them with `{Jumon.Live, NotebookWeb.Commands}`.
  See `Jumon.Commands`.

  These are the actions of the whole notebook. `NotebookWeb.NotebookLive`
  adds the actions of the page it shows. What each person runs is kept in
  the database, for "Recent" on any device.
  """
  use Jumon.Commands, history: {Jumon.History.Ecto, repo: Notebook.Repo}
  use NotebookWeb, :verified_routes

  alias Phoenix.LiveView.JS

  alias Notebook.{Pages, Spaces}
  alias Notebook.Accounts.Scope

  @impl true
  def actions(socket) do
    [
      action(:new_page, "New page",
        section: "Write",
        icon: "hero-plus",
        keywords: ~w(create write),
        shortcut: "c",
        navigate: ~p"/pages/new"
      ),
      action(:home, "All pages",
        section: "Go to",
        icon: "hero-home",
        keywords: ~w(home index),
        shortcut: "g h",
        navigate: ~p"/"
      ),
      action(:new_space, "New space",
        section: "Write",
        icon: "hero-squares-plus",
        keywords: ~w(create team folder),
        navigate: ~p"/spaces/new"
      ),
      action(:inbox, "Inbox",
        section: "Go to",
        icon: "hero-inbox",
        keywords: ~w(notifications mentions bell),
        shortcut: "g i",
        navigate: ~p"/inbox"
      ),
      action(:archive, "Archive",
        section: "Go to",
        icon: "hero-archive-box",
        keywords: ~w(archived deleted restore trash),
        navigate: ~p"/archive"
      ),
      action(:agents, "Agents",
        section: "Go to",
        icon: "notebook-robot",
        keywords: ~w(mcp claude codex token memory connect),
        shortcut: "g a",
        navigate: ~p"/agents"
      ),
      action(:settings, "Settings",
        section: "Go to",
        icon: "hero-cog-6-tooth",
        keywords: ~w(account email password),
        shortcut: "g s",
        navigate: ~p"/users/settings"
      ),
      action(:toggle_sidebar, "Hide or show the sidebar",
        section: "View",
        icon: "hero-view-columns",
        keywords: ~w(sidebar panel tree collapse expand),
        shortcut: "mod+\\",
        js: JS.dispatch("notebook:toggle-sidebar")
      ),
      action(:log_out, "Log out",
        section: "Account",
        icon: "hero-arrow-right-on-rectangle",
        keywords: ~w(sign out),
        href: ~p"/users/log-out",
        method: :delete
      )
    ] ++ if(admin?(socket), do: admin_actions(), else: [])
  end

  # Those of the notebook's admins only.
  defp admin_actions do
    [
      action(:bots, "Bots",
        section: "Go to",
        icon: "hero-sparkles",
        keywords: ~w(bot assistant ai),
        navigate: ~p"/bots"
      ),
      action(:notebook_settings, "Notebook settings",
        section: "Go to",
        icon: "hero-adjustments-horizontal",
        keywords: ~w(admin storage bucket invite invitation join register),
        navigate: ~p"/admin"
      )
    ]
  end

  # The pages the person may read, searched by their title and their
  # words. With an empty box, the pages changed last.
  @impl true
  def sources(socket) do
    scope = socket.assigns.current_scope

    [
      pages: [label: "Pages", search: &search_pages(scope, &1), min_length: 0],
      spaces: [label: "Spaces", search: &search_spaces(scope, &1), min_length: 0]
    ]
  end

  defp admin?(socket), do: Scope.admin?(socket.assigns.current_scope)

  # The spaces of the sidebar: go to one, or write a page in it.
  defp search_spaces(scope, query) do
    actions = scope |> Spaces.list() |> Enum.map(&space_action/1)

    case query do
      "" -> actions
      query -> actions |> Jumon.Match.rank(query) |> Enum.map(fn {action, _result} -> action end)
    end
  end

  defp space_action(space) do
    action("space-#{space.id}", space.name,
      icon: "hero-rectangle-stack",
      subtitle: "Space",
      navigate: ~p"/spaces/#{space.id}",
      actions: [
        action(:new_page, "New page here",
          icon: "hero-plus",
          navigate: ~p"/pages/new?space=#{space.id}"
        ),
        action(:members, "Members", icon: "hero-users", navigate: ~p"/spaces/#{space.id}/members")
      ]
    )
  end

  @impl true
  def history_key(socket), do: socket.assigns.current_scope.user.id

  defp search_pages(scope, ""),
    do: scope |> Pages.list() |> Enum.take(5) |> Enum.map(&page_action/1)

  # The titles are ranked as the palette ranks its actions, so that a typo
  # still finds a page ("notebok"); then the pages whose words have the
  # query. The notebook is small enough to rank every title.
  defp search_pages(scope, query) do
    by_title =
      Pages.list(scope)
      |> Enum.map(&page_action/1)
      |> Jumon.Match.rank(query)
      |> Enum.map(fn {action, _result} -> action end)

    by_words = scope |> Pages.list(search: query) |> Enum.map(&page_action/1)

    (by_title ++ by_words) |> Enum.uniq_by(& &1.id) |> Enum.take(8)
  end

  defp page_action(page) do
    action(page.id, page.title,
      icon: "hero-document-text",
      subtitle: page_subtitle(page),
      navigate: ~p"/pages/#{page.id}",
      actions: [
        action(:edit, "Edit together",
          icon: "hero-pencil-square",
          navigate: ~p"/pages/#{page.id}/edit"
        )
      ]
    )
  end

  defp page_subtitle(%{due_on: %Date{} = due} = page),
    do: "Due #{Calendar.strftime(due, "%-d %b")} · #{where(page)}"

  defp page_subtitle(page), do: where(page)

  defp where(%{space: %{name: space}} = page), do: "#{space} · #{author(page)}"
  defp where(page), do: author(page)

  defp author(%{author: %{name: name}}), do: name
  defp author(_page), do: "Notebook"
end
