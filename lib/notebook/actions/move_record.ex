defmodule Notebook.Actions.MoveRecord do
  @moduledoc false
  use Issho.Action,
    name: "move_record",
    description: """
    Moves a record in its database's order (the order of a table, and of a
    board's column), as the person you work for (they edit the page):
    after or before another record, or first or last.
    """,
    annotations: [idempotent: true]

  arg(:page_id, :integer,
    required: true,
    description: "The database page, as list_pages gives it"
  )

  arg(:id, :integer, required: true, description: "The record's id")
  arg(:after, :integer, description: "The record it goes after")
  arg(:before, :integer, description: "The record it goes before")
  arg(:to, {:enum, ["first", "last"]})

  alias Notebook.Actions
  alias Notebook.Cardbox, as: Box

  @impl Issho.Action
  def target(%{page_id: id}), do: Actions.room(id)

  @impl Issho.Action
  def run(%{page_id: page_id, id: id} = args, invocation) do
    with {:ok, scope, _page, collection} <- Actions.database(page_id, invocation) do
      case Box.move(collection, id, [{:actor, scope} | place(args)]) do
        {:ok, record} -> {:ok, record.id}
        {:error, error} -> {:error, error}
      end
    end
  end

  defp place(%{after: id}), do: [after: id]
  defp place(%{before: id}), do: [before: id]
  defp place(%{to: "first"}), do: [to: :first]
  defp place(_args), do: [to: :last]

  @impl Issho.Action
  def summary(id), do: %{"moved" => id}

  @impl Issho.Action
  def event(%{page_id: page}, id), do: %{page: page, record: id}
end
