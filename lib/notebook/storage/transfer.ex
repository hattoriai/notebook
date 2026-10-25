defmodule Notebook.Storage.Transfer do
  @moduledoc """
  Moves the files from one store to another (`Notebook.Storage.start_transfer/2`),
  a slice at a time: each job takes the files after the last it did, in
  the order of their keys, for at most two minutes (`:slice`, in
  milliseconds, in `config :notebook, Notebook.Storage.Transfer`), then leaves
  the rest to the next job. So a transfer of hours never holds a job for
  long (Oban's Lifeline would run it twice), outlasts a restart, and stops
  at its next files when an admin stops it. Its progress is kept as it
  goes (`Notebook.Storage.transfer/0`).

  The first job counts the files and their bytes, for the progress bar.
  """
  use Oban.Worker, queue: :storage, max_attempts: 10

  alias Notebook.Storage

  @batch 32
  @errors 20

  @doc false
  def enqueue(%{"run" => run, "after" => cursor} = transfer) do
    with {:ok, _job} <- %{"run" => run, "after" => cursor} |> new() |> Oban.insert(),
         do: {:ok, transfer}
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"run" => run}}) do
    case Storage.transfer() do
      %{"run" => ^run, "state" => state} = transfer when state in ["counting", "running"] ->
        transfer |> count() |> move(System.monotonic_time(:millisecond) + slice())

      _stopped_or_other ->
        :ok
    end
  end

  defp count(%{"state" => "counting"} = transfer) do
    {:ok, entries} = Storage.all(store(transfer["from"]))

    {total, bytes} =
      Enum.reduce(entries, {0, 0}, fn entry, {n, bytes} ->
        if rem(n + 1, 1000) == 0,
          do: Storage.broadcast({:storage, :transfer, %{transfer | "total" => n + 1}})

        {n + 1, bytes + entry.bytes}
      end)

    Storage.put_transfer(%{
      transfer
      | "state" => "running",
        "total" => total,
        "total_bytes" => bytes
    })
  end

  defp count(transfer), do: transfer

  defp move(transfer, deadline) do
    from = store(transfer["from"])
    to = store(transfer["to"])
    {:ok, entries} = Storage.all(from)
    cursor = transfer["after"]

    entries
    |> Stream.drop_while(&(cursor && &1.key <= cursor))
    |> Stream.chunk_every(@batch)
    |> Enum.reduce_while(transfer, fn batch, transfer ->
      results =
        batch
        |> Task.async_stream(&{&1, one(transfer["action"], &1, from, to)},
          max_concurrency: 4,
          timeout: :infinity
        )
        |> Enum.map(fn {:ok, result} -> result end)

      transfer = transfer |> tally(results) |> Map.put("after", List.last(batch).key)

      cond do
        stopped?(transfer) ->
          {:halt, {:stopped, transfer}}

        System.monotonic_time(:millisecond) > deadline ->
          {:halt, {:more, Storage.put_transfer(transfer)}}

        true ->
          {:cont, Storage.put_transfer(transfer)}
      end
    end)
    |> case do
      {:more, transfer} ->
        {:ok, _transfer} = enqueue(transfer)
        :ok

      {:stopped, transfer} ->
        # An admin stopped it while these files moved: what they did counts.
        Storage.put_transfer(%{transfer | "state" => "stopped"})
        :ok

      transfer ->
        Storage.put_transfer(%{
          transfer
          | "state" => "done",
            "finished_at" => DateTime.utc_now(:second) |> DateTime.to_iso8601()
        })

        :ok
    end
  end

  # One file: copied (or there already), or removed where the other store
  # has it, the same size.
  defp one("copy", entry, from, to) do
    case Storehouse.copy(entry.key, from: from, to: to) do
      {:ok, :copied} -> :moved
      {:ok, :skipped} -> :skipped
      {:error, reason} -> {:failed, reason}
    end
  end

  defp one("remove", %{key: key, bytes: bytes}, from, to) do
    case to.head(key) do
      {:ok, %{bytes: ^bytes}} ->
        case from.delete(key) do
          :ok -> :moved
          {:error, reason} -> {:failed, reason}
        end

      _missing_or_other ->
        :skipped
    end
  end

  defp tally(transfer, results) do
    Enum.reduce(results, transfer, fn {entry, result}, transfer ->
      transfer = %{
        transfer
        | "done" => transfer["done"] + 1,
          "done_bytes" => transfer["done_bytes"] + entry.bytes
      }

      case result do
        :moved ->
          %{transfer | "moved" => transfer["moved"] + 1}

        :skipped ->
          %{transfer | "skipped" => transfer["skipped"] + 1}

        {:failed, reason} ->
          errors =
            Enum.take(
              transfer["errors"] ++ [%{"key" => entry.key, "reason" => Storage.describe(reason)}],
              @errors
            )

          %{transfer | "failed" => transfer["failed"] + 1, "errors" => errors}
      end
    end)
  end

  defp stopped?(%{"run" => run}) do
    match?(%{"state" => "stopped"}, Storage.transfer()) or
      not match?(%{"run" => ^run}, Storage.transfer())
  end

  defp slice, do: Application.get_env(:notebook, __MODULE__, [])[:slice] || 120_000

  defp store("Storehouse.Local"), do: Storehouse.Local
  defp store("Storehouse.S3"), do: Storehouse.S3
end
