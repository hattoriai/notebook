defmodule NotebookWeb.MCPTest do
  use ExUnit.Case, async: true

  # An agent's client opens a stream of the MCP endpoint
  # (`subscriptions/listen`): Sake's registry of streams runs under
  # `{Sake, ...}` in the application's supervision tree.
  test "the MCP endpoint's streams are open to agents" do
    assert :ok = Sake.Plug.Streams.register_listen(NotebookWeb.MCP, "listen-1", %{})
    assert :ok = Sake.Plug.Streams.unregister_listen(NotebookWeb.MCP)
  end
end
