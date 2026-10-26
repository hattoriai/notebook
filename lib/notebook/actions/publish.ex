defmodule Notebook.Actions.Publish do
  @moduledoc false
  # A page or a folder published, at an address of its own. A person's
  # only, from the Publish dialog.
  use Issho.Action,
    name: "publish",
    description: "Publishes a page or a folder on the web, at its address (its slug)."

  arg(:kind, {:enum, ["page", "folder"]}, required: true)
  arg(:id, :integer, required: true)
  arg(:slug, :string, max_length: 120)

  alias Notebook.{Actions, Publishing}

  @impl Issho.Action
  def target(%{kind: kind, id: id}), do: Actions.room(kind, id)

  @impl Issho.Action
  def authorize(_args, who), do: Actions.person_only(who)

  @impl Issho.Action
  def run(%{kind: kind, id: id} = args, invocation) do
    with {:ok, scope} <- Actions.scope(invocation),
         resource when not is_nil(resource) <- Actions.resource(kind, id) do
      slug = args[:slug] && Publishing.slugify(args.slug)

      case Publishing.publish(scope, resource, slug) do
        {:ok, resource} -> {:ok, resource}
        {:error, reason} -> {:error, reason}
      end
    else
      nil -> {:error, "No such #{kind}."}
      error -> error
    end
  end

  @impl Issho.Action
  def event(%{kind: kind, id: id}, resource), do: %{kind: kind, id: id, slug: resource.slug}
end
