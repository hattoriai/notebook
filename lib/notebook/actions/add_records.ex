defmodule Notebook.Actions.AddRecords do
  @moduledoc false
  use Issho.Action,
    name: "add_records",
    description: """
    Adds records to a database page, as the person you work for (they edit
    the page): each one an object of values by field name or key, as
    read_database describes them. All of them are added, or none. Gives
    the records, with their ids.
    """

  arg(:page_id, :integer,
    required: true,
    description: "The database page, as list_pages gives it"
  )

  arg(:records, {:array, :any},
    required: true,
    description: ~s(The records' values, e.g. [{"Blade": "A short sword", "Status": "Asked"}])
  )

  alias Notebook.Actions
  alias Notebook.Cardbox, as: Box

  @impl Issho.Action
  def target(%{page_id: id}), do: Actions.room(id)

  @impl Issho.Action
  def run(%{page_id: id, records: records}, invocation) do
    with {:ok, scope, page} <- Actions.page(id, invocation),
         %Cardbox.Collection{} = collection <- Notebook.Databases.collection(page) do
      case Box.insert_all(collection, records, actor: scope) do
        {:ok, inserted} -> {:ok, {collection, inserted}}
        {:error, error} -> {:error, error}
      end
    else
      nil -> {:error, "That page is not a database."}
      error -> error
    end
  end

  @impl Issho.Action
  def summary({collection, records}),
    do: %{"records" => Enum.map(records, &Notebook.Tools.Databases.record(collection, &1))}

  @impl Issho.Action
  def event(%{page_id: id}, {_collection, records}), do: %{page: id, count: length(records)}
end
