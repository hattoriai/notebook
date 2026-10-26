defmodule Notebook.Actions.Unpublish do
  @moduledoc false
  # A published page or folder taken back. A person's only.
  use Issho.Action,
    name: "unpublish",
    description: "Takes a published page or folder off the web."

  arg(:kind, {:enum, ["page", "folder"]}, required: true)
  arg(:id, :integer, required: true)

  alias Notebook.Actions

  @impl Issho.Action
  def target(%{kind: kind, id: id}), do: Actions.room(kind, id)

  @impl Issho.Action
  def authorize(_args, who), do: Actions.person_only(who)

  @impl Issho.Action
  def run(%{kind: kind, id: id}, invocation) do
    with {:ok, scope} <- Actions.scope(invocation),
         resource when not is_nil(resource) <- Actions.resource(kind, id) do
      case Notebook.Publishing.unpublish(scope, resource) do
        {:ok, resource} -> {:ok, resource}
        {:error, reason} -> {:error, Actions.error(reason)}
      end
    else
      nil -> {:error, "No such #{kind}."}
      error -> error
    end
  end

  @impl Issho.Action
  def event(%{kind: kind, id: id}, _resource), do: %{kind: kind, id: id}
end
