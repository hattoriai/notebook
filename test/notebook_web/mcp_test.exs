defmodule NotebookWeb.MCPTest do
  use ExUnit.Case, async: true

  alias Sake.Plug.Streams

  # An agent's client opens a stream of the MCP endpoint
  # (`subscriptions/listen`): Sake's registry of streams runs under
  # `{Sake, ...}` in the application's supervision tree.
  test "the MCP endpoint's streams are open to agents" do
    assert :ok = Streams.register_listen(NotebookWeb.MCP, "listen-1", %{})
    assert :ok = Streams.unregister_listen(NotebookWeb.MCP)
  end
end
