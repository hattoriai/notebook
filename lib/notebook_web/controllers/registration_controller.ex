defmodule NotebookWeb.RegistrationController do
  use NotebookWeb, :controller
  alias Notebook.Invitations
  alias NotebookWeb.UserAuth

  def create(conn, %{"user" => params} = all) do
    invite = all["invite"]

    case Invitations.register(params, invite) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Welcome to Notebook, #{user.name}.")
        |> UserAuth.log_in_user(user)

      {:error, :invite_only} ->
        conn
        |> put_flash(:error, "This notebook is invite only, and this link does not work.")
        |> redirect(to: ~p"/users/register")

      {:error, changeset} ->
        message =
          changeset.errors
          |> Enum.map(fn {field, {reason, _}} -> "#{field} #{reason}" end)
          |> Enum.join(", ")

        conn
        |> put_flash(:error, message)
        |> redirect(to: register_path(invite))
    end
  end

  defp register_path(invite) when is_binary(invite) and invite != "",
    do: ~p"/users/register?#{[invite: invite]}"

  defp register_path(_invite), do: ~p"/users/register"
end
