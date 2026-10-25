defmodule Notebook.Storage.Copy do
  @moduledoc """
  Copies the files of the store the notebook left (`Notebook.Storage.other/0`)
  to the one it keeps them in now, under the same keys, so that their
  addresses hold. A file already there is skipped: the job can run again.
  The settings page sees its progress.
  """
  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 60, states: :incomplete]

  alias Notebook.Storage

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case Storage.other() do
      nil ->
        :ok

      from ->
        count = :counters.new(1, [])

        progress = fn _key, _result ->
          :counters.add(count, 1, 1)
          n = :counters.get(count, 1)
          if rem(n, 10) == 0, do: Storage.broadcast({:storage, :copying, n})
        end

        with {:ok, result} <-
               Storehouse.copy_prefix("",
                 from: from,
                 to: Storage.adapter(),
                 on_progress: progress
               ) do
          Storage.copied(%{
            "copied" => result.copied,
            "skipped" => result.skipped,
            "failed" => length(result.failed),
            "at" => DateTime.utc_now(:second) |> DateTime.to_iso8601()
          })

          :ok
        end
    end
  end
end
