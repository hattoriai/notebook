defmodule NotebookWeb.CollabSocket do
  use Phoenix.Socket
  channel "kotoba:*", NotebookWeb.CollabChannel
  def connect(_params, socket, _connect_info), do: {:ok, socket}
  def id(_socket), do: nil
end
