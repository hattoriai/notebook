defmodule NotebookWeb.RequireAdmin do
  @moduledoc """
  A page of the notebook's own settings, for its admins only: others go
  back to their pages. After `{NotebookWeb.UserAuth, :require_authenticated}`.
  """

  import Phoenix.LiveView

  alias Notebook.Accounts.Scope

  def on_mount(:default, _params, _session, socket) do
    if Scope.admin?(socket.assigns[:current_scope]) do
      {:cont, socket}
    else
      {:halt,
       socket
       |> put_flash(:error, "Only the notebook's admins change its settings.")
       |> redirect(to: "/")}
    end
  end
end
