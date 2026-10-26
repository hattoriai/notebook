defmodule Notebook.Actions.ShareLink do
  @moduledoc false
  # What anyone with a page's or a folder's link may do, or no link. A
  # person's only, from the Share dialog.
  use Issho.Action,
    name: "share_link",
    description:
      "Gives a page or a folder a link anyone may follow, as a reader or a commenter, or takes it away."

  arg(:kind, {:enum, ["page", "folder"]}, required: true)
  arg(:id, :integer, required: true)
  arg(:role, {:enum, ["viewer", "commenter", "off"]}, required: true)

  alias Notebook.{Actions, Sharing}

  @impl Issho.Action
  def target(%{kind: kind, id: id}), do: Actions.room(kind, id)

  @impl Issho.Action
  def authorize(_args, who), do: Actions.person_only(who)

  @impl Issho.Action
  def run(%{kind: kind, id: id, role: role}, invocation) do
    with {:ok, scope} <- Actions.scope(invocation),
         resource when not is_nil(resource) <- Actions.resource(kind, id) do
      link(scope, resource, role)
    else
      nil -> {:error, "No such #{kind}."}
      error -> error
    end
  end

  defp link(scope, resource, "off") do
    case Sharing.unlink(scope, resource) do
      :ok -> {:ok, nil}
      {:error, reason} -> {:error, Actions.error(reason)}
    end
  end

  defp link(scope, resource, role) do
    case Sharing.link(scope, resource, role) do
      {:ok, token} -> {:ok, Sharing.url(resource, token)}
      {:error, reason} -> {:error, Actions.error(reason)}
    end
  end

  @impl Issho.Action
  def event(%{kind: kind, id: id, role: role}, _url), do: %{kind: kind, id: id, role: role}
end
