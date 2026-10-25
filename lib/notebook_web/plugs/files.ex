defmodule NotebookWeb.Plugs.Files do
  @moduledoc """
  The pages' files at their addresses (`/uploads/kotoba/<key>`), from the
  store that has each (`Notebook.Storage.store_of/1`): this server's
  disk, or the bucket, sent through the notebook (`Storehouse.Proxy`) or
  to a link the bucket signs for a few minutes (`Storehouse.Redirect`).
  Who may read a file is `NotebookWeb.Plugs.Uploads`'s, before this.
  """
  @behaviour Plug

  alias Notebook.Storage

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{path_info: ["uploads", "kotoba" | parts]} = conn, _opts) do
    case Storage.store_of(Enum.join(parts, "/")) do
      Storehouse.Local ->
        Storehouse.Local.Plug.call(conn, Storehouse.Local.Plug.init(at: Storage.prefix()))

      bucket ->
        plug = if Storage.serve() == "redirect", do: Storehouse.Redirect, else: Storehouse.Proxy
        plug.call(%{conn | path_info: parts}, plug.init(authorize: true, adapter: bucket))
    end
  end
end
