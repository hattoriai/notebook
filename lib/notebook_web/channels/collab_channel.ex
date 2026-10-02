defmodule NotebookWeb.CollabChannel do
  use Kotoba.Collab.Channel, supervisor: Notebook.CollabSupervisor

  def authorize(socket, page_id, _action) do
    with %{"id" => id} <- socket.assigns.kotoba_collab_user,
         {user_id, ""} <- Integer.parse(id),
         %Notebook.Accounts.User{} <- Notebook.Repo.get(Notebook.Accounts.User, user_id),
         %Notebook.Pages.Page{} <- Notebook.Pages.get(page_id) do
      :ok
    else
      _ -> {:error, :forbidden}
    end
  end
end
