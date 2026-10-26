defmodule NotebookWeb.Plugs.Guest do
  @moduledoc """
  A visitor of the published pages, signed in nowhere, is one guest
  (`Issho.Guests`) for its browser's session: the key it asks the pages'
  bots with, the same however often it comes back.
  """
  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case get_session(conn, "guest") do
      "guest:" <> _ -> conn
      _ -> put_session(conn, "guest", Issho.Guests.new().id)
    end
  end
end
