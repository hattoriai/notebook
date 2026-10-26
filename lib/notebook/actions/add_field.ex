defmodule Notebook.Actions.AddField do
  @moduledoc false
  use Issho.Action,
    name: "add_field",
    description: """
    Adds a field to a database page, as the person you work for (they edit
    the page): its name, and its type; a number's format (and a currency's
    code), a repeat's date and done fields (their keys, the page's own
    unless given).
    """

  arg(:page_id, :integer,
    required: true,
    description: "The database page, as list_pages gives it"
  )

  arg(:name, :string, required: true, min_length: 1, max_length: 60)

  arg(:type, {:enum, Enum.map(Notebook.Databases.field_types(), &elem(&1, 0))}, required: true)

  arg(:format, {:enum, ["number", "integer", "percent", "currency"]},
    description: "A number's format"
  )

  arg(:currency, :string, max_length: 3, description: ~s(A currency's code, "JPY"))
  arg(:date, :string, max_length: 60, description: "A repeat's date field")
  arg(:done, :string, max_length: 60, description: "A repeat's done field")

  alias Notebook.Actions

  @impl Issho.Action
  def target(%{page_id: id}), do: Actions.room(id)

  @impl Issho.Action
  def run(%{page_id: id} = args, invocation) do
    params =
      for {key, value} <- Map.take(args, [:name, :type, :format, :currency, :date, :done]),
          into: %{},
          do: {to_string(key), value}

    with {:ok, scope, _page, collection} <- Actions.database(id, invocation) do
      case Notebook.Databases.add_field(scope, collection, params) do
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
