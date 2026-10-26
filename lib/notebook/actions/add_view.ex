defmodule Notebook.Actions.AddView do
  @moduledoc false
  use Issho.Action,
    name: "add_view",
    description: """
    Adds a view to a database page, as the person you work for (they edit
    the page): a table, a board (by a status or select field), a calendar
    (by a date field) or a chart.
    """

  arg(:page_id, :integer,
    required: true,
    description: "The database page, as list_pages gives it"
  )

  arg(:type, {:enum, Enum.map(Notebook.Databases.view_types(), &elem(&1, 0))}, required: true)

  alias Notebook.Actions

  @impl Issho.Action
  def target(%{page_id: id}), do: Actions.room(id)

  @impl Issho.Action
  def run(%{page_id: id, type: type}, invocation) do
    with {:ok, scope, _page, collection} <- Actions.database(id, invocation) do
      case Notebook.Databases.add_view(scope, collection, type) do
        {:ok, view} -> {:ok, view}
        {:error, error} -> {:error, Actions.error(error)}
      end
    end
  end

  @impl Issho.Action
  def summary(view), do: %{"view" => view.name, "id" => view.id, "type" => view.type}

  @impl Issho.Action
  def event(%{page_id: id}, view), do: %{page: id, view: view.id}
end
