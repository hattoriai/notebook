defmodule Notebook.Actions.UpdateRecords do
  @moduledoc false
  use Issho.Action,
    name: "update_records",
    description: """
    Changes records of a database page, as the person you work for (they
    edit the page): each change names a record's id and the values to give
    it, by field name or key; null empties a value. Gives the records as
    they are after it.
    """,
    annotations: [idempotent: true]

  arg(:page_id, :integer,
    required: true,
    description: "The database page, as list_pages gives it"
  )

  arg(
    :changes,
    {:array,
     {:object,
      [
        {:id, :integer, required: true, description: "The record's id"},
        {:values, :any, required: true, description: ~s(e.g. {"Status": "Delivered"})},
        {:expect, :any, description: "The values you saw: changed since, it is refused"}
      ]}},
    required: true
  )

  alias Notebook.Actions
  alias Notebook.Cardbox, as: Box

  @impl Issho.Action
  def target(%{page_id: id}), do: Actions.room(id)

  @impl Issho.Action
  def run(%{page_id: id, changes: changes}, invocation) do
    with {:ok, scope, _page, collection} <- Actions.database(id, invocation) do
      # Each change is guarded: an agent paused halfway makes no more.
      changes
      |> Enum.reduce_while({:ok, []}, fn change, {:ok, done} ->
        case guard(invocation, fn -> update(collection, change, scope) end) do
          {:ok, record} -> {:cont, {:ok, [record | done]}}
          {:error, reason} -> {:halt, halted(reason, done)}
        end
      end)
      |> case do
        {:ok, records} -> {:ok, {collection, Enum.reverse(records)}}
        error -> error
      end
    end
  end

  defp update(collection, %{id: id, values: values} = change, scope) do
    opts =
      if is_map(change[:expect]), do: [actor: scope, expect: change.expect], else: [actor: scope]

    Box.update(collection, id, values, opts)
  end

  defp guard(%{participant: nil}, fun), do: fun.()
  defp guard(%{participant: participant}, fun), do: Issho.Work.guard(participant, fun)

  # The first change's refusal as it is (Cardbox's, which a table reads);
  # a later one's in words, with what was made before it.
  defp halted(reason, []), do: {:error, reason}

  defp halted(reason, done),
    do:
      {:error,
       "#{Issho.Action.message(reason)} (#{length(done)} of the changes were made before.)"}

  @impl Issho.Action
  def summary({collection, records}),
    do: %{"records" => Enum.map(records, &Notebook.Tools.Databases.record(collection, &1))}

  @impl Issho.Action
  def event(%{page_id: id}, {_collection, records}), do: %{page: id, count: length(records)}
end
