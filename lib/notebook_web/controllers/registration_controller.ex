defmodule NotebookWeb.RegistrationController do
  use NotebookWeb, :controller
  alias Notebook.Accounts
  alias NotebookWeb.UserAuth

  def create(conn, %{"user" => params}) do
    case Accounts.register_user(params) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Welcome to Notebook, #{user.name}.")
        |> UserAuth.log_in_user(user)

      {:error, changeset} ->
        message =
          changeset.errors
          |> Enum.map(fn {field, {reason, _}} -> "#{field} #{reason}" end)
          |> Enum.join(", ")

        conn
        |> put_flash(:error, message)
        |> redirect(to: ~p"/users/register")
    end
  end
end
