defmodule Notebook.Actions.Share do
  @moduledoc false
  # Who has a page or a folder: a person given a role, or taken off it
  # ("none"). A person's only, from the Share dialog.
  use Issho.Action,
    name: "share",
    description: "Shares a page or a folder with a person, as a reader, a commenter or an editor."

  arg(:kind, {:enum, ["page", "folder"]}, required: true)
  arg(:id, :integer, required: true)
  arg(:user_id, :integer, required: true)
  arg(:role, {:enum, ["viewer", "commenter", "editor", "none"]}, required: true)

  alias Notebook.Accounts.User
  alias Notebook.{Actions, Sharing}

  @impl Issho.Action
  def target(%{kind: kind, id: id}), do: Actions.room(kind, id)

  @impl Issho.Action
  def authorize(_args, who), do: Actions.person_only(who)

  @impl Issho.Action
  def run(%{kind: kind, id: id, user_id: user_id, role: role}, invocation) do
    with {:ok, scope} <- Actions.scope(invocation),
         resource when not is_nil(resource) <- Actions.resource(kind, id),
         %User{} = user <- Notebook.Repo.get(User, user_id) do
      share(scope, resource, user, role)
    else
      nil -> {:error, "No such #{kind} or person."}
      error -> error
    end
  end

  defp share(scope, resource, user, "none") do
    case Sharing.unshare(scope, resource, user) do
      :ok -> {:ok, :unshared}
      {:error, reason} -> {:error, Actions.error(reason)}
    end
  end

  defp share(scope, resource, user, role) do
    case Sharing.share(scope, resource, user, role) do
      {:ok, _grant} -> {:ok, role}
      {:error, reason} -> {:error, Actions.error(reason)}
    end
  end

  @impl Issho.Action
  def event(%{kind: kind, id: id, user_id: user_id}, role),
    do: %{kind: kind, id: id, user: user_id, role: to_string(role)}
end
