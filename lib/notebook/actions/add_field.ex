defmodule Notebook.Actions.AddField do
  @moduledoc false
  use Issho.Action,
    name: "add_field",
    description: """
    Adds a field to a database page, as the person you work for (they edit
    the page): its name, and its type.
    """

  arg(:page_id, :integer,
    required: true,
    description: "The database page, as list_pages gives it"
  )

  arg(:name, :string, required: true, min_length: 1, max_length: 60)

  arg(:type, {:enum, Enum.map(Notebook.Databases.field_types(), &elem(&1, 0))}, required: true)

  alias Notebook.Actions

  @impl Issho.Action
  def target(%{page_id: id}), do: Actions.room(id)

  @impl Issho.Action
  def run(%{page_id: id, name: name, type: type}, invocation) do
    with {:ok, scope, _page, collection} <- Actions.database(id, invocation) do
      case Notebook.Databases.add_field(scope, collection, %{"name" => name, "type" => type}) do
        {:ok, collection} -> {:ok, collection}
        {:error, error} -> {:error, Actions.error(error)}
      end
    end
  end

  @impl Issho.Action
  def summary(collection), do: Cardbox.describe(collection)

  @impl Issho.Action
  def event(%{page_id: id, name: name}, _collection), do: %{page: id, field: name}
end
