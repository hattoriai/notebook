defmodule NotebookWeb.Plugs.Uploads do
  @moduledoc """
  Who reads a page's file: anyone signed in (the notebook's own pages
  check what they show), and anyone at all for a file a published page
  shows (`Notebook.Publishing.public_upload?/1`). Anyone else gets a 404.
  """
  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%{assigns: %{current_scope: %{user: %{}}}} = conn, _opts), do: conn

  def call(%{path_info: ["uploads", "kotoba" | key]} = conn, _opts) do
    if key != [] and Notebook.Publishing.public_upload?(Enum.join(key, "/")),
      do: conn,
      else: conn |> send_resp(404, "Not found") |> halt()
  end

  def call(conn, _opts), do: conn |> send_resp(404, "Not found") |> halt()
end
