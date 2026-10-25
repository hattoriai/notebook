defmodule Notebook.Storage.Prune do
  @moduledoc """
  Removes from the store the notebook left (`Notebook.Storage.other/0`)
  the files its store has now, the same size: once copied, they take no
  room there. A file the store does not have is kept.
  """
  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 60, states: :incomplete]

  alias Notebook.Storage

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    with from when not is_nil(from) <- Storage.other(),
         {:ok, entries} <- Storage.all(from) do
      to = Storage.adapter()

      removed =
        Enum.count(entries, fn %{key: key, bytes: bytes} ->
          with {:ok, %{bytes: ^bytes}} <- to.head(key),
               :ok <- from.delete(key),
               do: true,
               else: (_ -> false)
        end)

      Storage.pruned(removed)
      :ok
    else
      nil -> :ok
      error -> error
    end
  end
end
