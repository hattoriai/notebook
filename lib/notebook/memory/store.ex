defmodule Notebook.Memory.Store do
  @moduledoc """
  An agent's memory as a filesystem (`VFS.Mountable`), mounted at
  `/memories` in its bash (`Notebook.Memory.Shell`). A command reads the
  agent's files in one query, the first time it needs them, and keeps
  them for the rest of the command (its snapshot); every write goes to
  the database at once (`Notebook.Memory`) and the next read reads again.
  A store lives for one command: the next starts from the database, so
  what its person changed meanwhile is what the agent reads.
  """
  @enforce_keys [:agent_id]
  defstruct [:agent_id, snapshot: nil]

  @doc "The memory of an agent, as a mount."
  def new(agent_id), do: %__MODULE__{agent_id: agent_id}

  @doc false
  # The agent's files and directories, by path, read once per command.
  def load(%__MODULE__{snapshot: nil, agent_id: id} = store) do
    case Process.get({__MODULE__, id}) do
      nil ->
        store = read(store)
        if Process.get({__MODULE__, :command}), do: Process.put({__MODULE__, id}, store.snapshot)
        store

      snapshot ->
        %{store | snapshot: snapshot}
    end
  end

  def load(store), do: store

  @doc """
  Runs `fun` as one command: the snapshot read the first time is kept for
  the rest of it, in the process (a command's reads do not all hand back
  the store they were given), and dropped at each write and at its end.
  """
  def command(fun) do
    Process.put({__MODULE__, :command}, true)

    try do
      fun.()
    after
      for {{__MODULE__, _} = key, _} <- Process.get(), do: Process.delete(key)
    end
  end

  @doc false
  def forget(%__MODULE__{agent_id: id} = store) do
    Process.delete({__MODULE__, id})
    %{store | snapshot: nil}
  end

  defp read(%__MODULE__{agent_id: id} = store) do
    rows = Notebook.Memory.files(id)
    files = for f <- rows, not f.directory, into: %{}, do: {f.path, f}

    dirs =
      rows
      |> Enum.flat_map(fn f ->
        if f.directory, do: [f.path | ancestors(f.path)], else: ancestors(f.path)
      end)
      |> MapSet.new()
      |> MapSet.put("/")

    %{store | snapshot: %{files: files, dirs: dirs}}
  end

  @doc false
  def ancestors(path) do
    case Path.dirname(path) do
      "/" -> []
      up -> [up | ancestors(up)]
    end
  end
end

defimpl VFS.Mountable, for: Notebook.Memory.Store do
  use VFS.Skeleton

  alias Notebook.Memory
  alias Notebook.Memory.Store
  alias VFS.{Error, Stat}

  @dir_stat %Stat{type: :directory, size: 0, mtime: DateTime.from_unix!(0)}

  def materialize(store, _opts), do: {:ok, Store.load(store)}

  def exists?(store, path) do
    %{snapshot: snap} = store = Store.load(store)
    p = VFS.Path.normalize(path)
    {Map.has_key?(snap.files, p) or MapSet.member?(snap.dirs, p), store}
  end

  def stat(store, path) do
    %{snapshot: snap} = store = Store.load(store)
    p = VFS.Path.normalize(path)

    cond do
      file = snap.files[p] -> {:ok, file_stat(file), store}
      MapSet.member?(snap.dirs, p) -> {:ok, @dir_stat, store}
      true -> {:error, Error.new(:enoent, path: p)}
    end
  end

  def readdir(store, path) do
    %{snapshot: snap} = store = Store.load(store)
    p = VFS.Path.normalize(path)

    cond do
      Map.has_key?(snap.files, p) ->
        {:error, Error.new(:enotdir, path: p)}

      MapSet.member?(snap.dirs, p) ->
        prefix = if p == "/", do: "/", else: p <> "/"

        names =
          (Map.keys(snap.files) ++ MapSet.to_list(snap.dirs))
          |> Enum.filter(&(&1 != p and String.starts_with?(&1, prefix)))
          |> Enum.map(&(&1 |> String.replace_prefix(prefix, "") |> String.split("/") |> hd()))
          |> Enum.uniq()
          |> Enum.sort()

        {:ok, names, store}

      true ->
        {:error, Error.new(:enoent, path: p)}
    end
  end

  def stream_read(store, path, opts) do
    %{snapshot: snap} = store = Store.load(store)
    p = VFS.Path.normalize(path)

    cond do
      file = snap.files[p] ->
        case VFS.StreamOptions.apply(file.content || "", opts) do
          {:ok, stream} -> {:ok, stream, store}
          {:error, reason} -> {:error, Error.new(reason, path: p)}
        end

      MapSet.member?(snap.dirs, p) ->
        {:error, Error.new(:eisdir, path: p)}

      true ->
        {:error, Error.new(:enoent, path: p)}
    end
  end

  # Everything under a directory, its directories too, from the snapshot.
  def walk(store, root, _opts) do
    %{snapshot: snap} = Store.load(store)
    p = VFS.Path.normalize(root)
    prefix = if p == "/", do: "/", else: p <> "/"

    dirs = for d <- snap.dirs, d != p, String.starts_with?(d, prefix), do: {d, @dir_stat}

    files =
      for {path, f} <- snap.files, String.starts_with?(path, prefix), do: {path, file_stat(f)}

    Enum.sort_by(dirs ++ files, &elem(&1, 0))
  end

  def write_file(store, path, content, _opts) when is_binary(content) do
    p = VFS.Path.normalize(path)

    case Memory.write(store.agent_id, p, content) do
      {:ok, _file} -> {:ok, Store.forget(store)}
      {:error, kind} -> {:error, error(kind, p)}
    end
  end

  def mkdir(store, path, opts) do
    p = VFS.Path.normalize(path)

    case Memory.mkdir(store.agent_id, p, parents: Keyword.get(opts, :parents, false)) do
      {:ok, _file} -> {:ok, Store.forget(store)}
      {:error, kind} -> {:error, error(kind, p)}
    end
  end

  def rm(store, path, opts) do
    p = VFS.Path.normalize(path)

    case Memory.rm(store.agent_id, p, recursive: Keyword.get(opts, :recursive, false)) do
      {:ok, _} -> {:ok, Store.forget(store)}
      {:error, kind} -> {:error, error(kind, p)}
    end
  end

  def capabilities(_store), do: MapSet.new([:read, :write, :mkdir, :native_walk, :lazy])

  defp file_stat(file) do
    %Stat{
      type: :regular,
      size: byte_size(file.content || ""),
      mtime: file.updated_at || DateTime.from_unix!(0)
    }
  end

  # A file's own refusals, in the words a shell has for them.
  defp error(:eacces, p),
    do: Error.new(:eacces, path: p, message: "#{p} is your person's to write")

  defp error(:efbig, p),
    do: Error.new(:eio, path: p, message: "#{p}: a memory file holds at most 64 KB")

  defp error(:enospc, p),
    do: Error.new(:eio, path: p, message: "#{p}: your memory is full, tidy it first")

  defp error(kind, p), do: Error.new(kind, path: p)
end
