defmodule Notebook.Cardbox.People do
  @moduledoc """
  The Notebook's Cardbox as a person's database views use it: what they
  read is Cardbox's (`Notebook.Cardbox`), what they write is the
  Notebook's actions (`Notebook.Actions`), run as the person in the
  page's room, the same as their agent's tools: a row added, a cell
  changed or a row deleted in the table (Masu), a card moved on the
  board (Narabe). Each is heard in the room as `"action.done"`, by them.

  The views get it as their `cardbox` (`Cardbox.Masu.table/1`,
  `Cardbox.Narabe.handle_move/6`), in the LiveView's process, which is in
  the page's room (`Issho.Live.act/3`).
  """

  alias Notebook.Actions
  alias Notebook.Cardbox, as: Box

  # What the views read, and the module's own: Cardbox's.
  defdelegate __cardbox__(key), to: Box
  defdelegate actor_id(actor), to: Box
  defdelegate allow?(actor, action, subject), to: Box
  defdelegate check_view(type, options, collection), to: Box
  defdelegate get(collection, id), to: Box
  defdelegate list(collection, query \\ nil, opts \\ []), to: Box
  defdelegate count(collection, query \\ nil, opts \\ []), to: Box
  defdelegate group(collection, query \\ nil, opts), to: Box
  defdelegate titles(collection_id, ids), to: Box
  defdelegate get_view(collection, id), to: Box
  defdelegate update_view(collection, view, attrs, opts \\ []), to: Box

  @doc "A row added: `add_records`, as the person."
  def insert(collection, values, _opts \\ []) do
    with {:ok, {_collection, [record]}} <-
           act(Actions.AddRecords, %{page_id: page(collection), records: [values]}),
         do: {:ok, record}
  end

  @doc "A row's cells changed: `update_records`, with what the person saw (`expect`)."
  def update(collection, record, changes, opts \\ []) do
    change =
      %{id: id(record), values: changes}
      |> then(&if(opts[:expect], do: Map.put(&1, :expect, opts[:expect]), else: &1))

    with {:ok, {_collection, [record]}} <-
           act(Actions.UpdateRecords, %{page_id: page(collection), changes: [change]}),
         do: {:ok, record}
  end

  @doc "A row deleted: `delete_records`, as the person."
  def delete(collection, record, _opts \\ []) do
    with {:ok, [id]} <-
           act(Actions.DeleteRecords, %{page_id: page(collection), ids: [id(record)]}),
         do: {:ok, %{id: id}}
  end

  @doc "A card moved in the order: `move_record`, as the person."
  def move(collection, record, opts) do
    place =
      cond do
        opts[:after] -> %{after: id(opts[:after])}
        opts[:before] -> %{before: id(opts[:before])}
        opts[:to] == :first -> %{to: "first"}
        true -> %{to: "last"}
      end

    args = Map.merge(%{page_id: page(collection), id: id(record)}, place)

    with {:ok, id} <- act(Actions.MoveRecord, args), do: {:ok, Box.get(collection, id)}
  end

  defp act(action, args) do
    case Issho.Live.act(action, args) do
      {:ok, receipt} -> {:ok, receipt.result}
      {:error, reason} -> {:error, error(reason)}
    end
  end

  # A refusal as the views show one: Cardbox's error, in words.
  defp error(%Cardbox.Error{} = error), do: error

  defp error(reason) do
    message = Issho.Action.message(reason)

    if message =~ "changed since",
      do: %Cardbox.Error{reason: :conflict, message: message},
      else: %Cardbox.Error{reason: :invalid, message: message}
  end

  defp page(%Cardbox.Collection{owner_type: "page", owner_id: id}), do: to_id(id)

  defp id(%{id: id}), do: id
  defp id(id), do: to_id(id)

  defp to_id(id) when is_integer(id), do: id
  defp to_id(id), do: String.to_integer(to_string(id))
end
