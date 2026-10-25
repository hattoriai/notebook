defmodule NotebookWeb.Plugs.Feed do
  @moduledoc "A published blog's RSS feed, at its path and `/feed.xml` (`Notebook.Publishing`)."
  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%{path_info: words} = conn, _opts) do
    with "feed.xml" <- List.last(words),
         {:feed, folder, posts} <- Notebook.Publishing.resolve(words) do
      conn
      |> put_resp_content_type("application/rss+xml")
      |> send_resp(200, Notebook.Publishing.feed(folder, posts))
      |> halt()
    else
      _ -> conn
    end
  end
end
