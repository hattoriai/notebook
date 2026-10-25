defmodule Notebook.Storage.Usage do
  @moduledoc """
  How much room the notebook takes, to choose where its files are kept:
  this server's disk (its size and what is free, by `df`), the files in a
  store (counted, which takes a while for many), and the database.
  """

  @doc """
  The disk that holds `path`: `%{total: bytes, used: bytes, free: bytes}`,
  or nil where `df` can't tell.
  """
  def disk(path) do
    path = existing(path)

    with {out, 0} <- System.cmd("df", ["-Pk", path], stderr_to_stdout: true),
         [_header, line | _rest] <- String.split(out, "\n", trim: true),
         [_fs, total, used, free | _rest] <- String.split(line) do
      %{total: kb(total), used: kb(used), free: kb(free)}
    else
      _other -> nil
    end
  rescue
    _error -> nil
  end

  @doc "The files of `store`: `%{count: n, bytes: bytes}`."
  def files(store) do
    case Notebook.Storage.all(store) do
      {:ok, entries} ->
        Enum.reduce(entries, %{count: 0, bytes: 0}, fn entry, acc ->
          %{count: acc.count + 1, bytes: acc.bytes + entry.bytes}
        end)

      {:error, _reason} ->
        nil
    end
  rescue
    _error -> nil
  end

  @doc "The database's file and its write-ahead log, in bytes."
  def database do
    path = Notebook.Repo.config()[:database]

    Enum.sum_by(["", "-wal"], fn suffix ->
      case File.stat(path <> suffix) do
        {:ok, %{size: size}} -> size
        _missing -> 0
      end
    end)
  end

  @doc "The directory of the files on this server."
  def root, do: Storehouse.Local.config()[:root]

  @doc "Bytes, as people read them: 1.2 GB."
  def human(nil), do: "–"
  def human(bytes) when bytes < 1024, do: "#{bytes} B"

  def human(bytes) do
    {value, unit} =
      Enum.reduce_while(~w(KB MB GB TB PB), bytes / 1024, fn unit, value ->
        if value < 1024, do: {:halt, {value, unit}}, else: {:cont, value / 1024}
      end)
      |> case do
        {value, unit} -> {value, unit}
        value -> {value, "PB"}
      end

    "#{if value < 10, do: Float.round(value, 1), else: round(value)} #{unit}"
  end

  # The path, or the nearest directory above it that is there: a root not
  # made yet is on the disk of its parent.
  defp existing(path) do
    cond do
      File.exists?(path) -> path
      Path.dirname(path) == path -> path
      true -> existing(Path.dirname(path))
    end
  end

  defp kb(n), do: String.to_integer(n) * 1024
end
