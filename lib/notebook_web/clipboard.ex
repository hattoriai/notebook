defmodule NotebookWeb.Clipboard do
  @moduledoc """
  The toast of a copy button (`NotebookWeb.CoreComponents.copy_button/1`)
  in every LiveView: the browser copies, then says what it copied, or
  that it could not.
  """

  import Phoenix.LiveView

  def on_mount(:default, _params, _session, socket),
    do: {:cont, attach_hook(socket, :clipboard, :handle_event, &handle_event/3)}

  defp handle_event("clipboard:copied", %{"what" => what}, socket),
    do: {:halt, put_flash(socket, :info, "#{what} copied to your clipboard")}

  defp handle_event("clipboard:copy_failed", %{"what" => what}, socket),
    do:
      {:halt,
       put_flash(
         socket,
         :error,
         "Could not copy the #{String.downcase(what)}. Allow clipboard access and try again."
       )}

  defp handle_event(_event, _params, socket), do: {:cont, socket}
end
