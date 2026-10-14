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

  alias Notebook.Pages

  @impl true
  def actions(_socket) do
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
      action(:settings, "Settings",
        section: "Go to",
        icon: "hero-cog-6-tooth",
        keywords: ~w(account email password),
        shortcut: "g s",
        navigate: ~p"/users/settings"
      ),
      action(:log_out, "Log out",
        section: "Account",
        icon: "hero-arrow-right-on-rectangle",
        keywords: ~w(sign out),
        href: ~p"/users/log-out",
        method: :delete
      )
    ]
  end

  # The pages, searched by their title and their words. With an empty box,
  # the pages changed last.
  @impl true
  def sources(_socket) do
    [pages: [label: "Pages", search: &search_pages/1, min_length: 0]]
  end

  @impl true
  def history_key(socket), do: socket.assigns.current_scope.user.id

  defp search_pages(""), do: Pages.list() |> Enum.take(5) |> Enum.map(&page_action/1)

  # The titles are ranked as the palette ranks its actions, so that a typo
  # still finds a page ("notebok"); then the pages whose words have the
  # query. The notebook is small enough to rank every title.
  defp search_pages(query) do
    by_title =
      Pages.list()
      |> Enum.map(&page_action/1)
      |> Jumon.Match.rank(query)
      |> Enum.map(fn {action, _result} -> action end)

    by_words = query |> Pages.list() |> Enum.map(&page_action/1)

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
    do: "Due #{Calendar.strftime(due, "%-d %b")} · #{author(page)}"

  defp page_subtitle(page), do: author(page)

  defp author(%{author: %{name: name}}), do: name
  defp author(_page), do: "Notebook"
end
