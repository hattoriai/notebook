defmodule Notebook.Actions.DeleteRecords do
  @moduledoc false
  use Issho.Action,
    name: "delete_records",
    description: """
    Deletes records of a database page, by id, as the person you work for
    (they edit the page), and the links to them.
    """,
    annotations: [destructive: true]

  arg(:page_id, :integer,
    required: true,
    description: "The database page, as list_pages gives it"
  )

  arg(:ids, {:array, :integer}, required: true, description: "The records' ids")

  alias Notebook.Actions
  alias Notebook.Cardbox, as: Box

  @impl Issho.Action
  def target(%{page_id: id}), do: Actions.room(id)

  @impl Issho.Action
  def run(%{page_id: id, ids: ids}, invocation) do
    with {:ok, scope, _page, collection} <- Actions.database(id, invocation) do
      Enum.reduce_while(ids, {:ok, []}, fn record, {:ok, done} ->
        case Box.delete(collection, record, actor: scope) do
          {:ok, deleted} -> {:cont, {:ok, [deleted.id | done]}}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)
    end
  end

  @impl Issho.Action
  def summary(ids), do: %{"deleted" => Enum.reverse(ids)}

  @impl Issho.Action
  def event(%{page_id: id}, ids), do: %{page: id, count: length(ids)}
end
