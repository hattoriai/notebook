defmodule Notebook.Memory do
  @moduledoc """
  What an agent remembers between its sessions: files of its own, under
  `/memories`, kept in the database. The agent reads and writes them
  with a bash of its own (`Notebook.Memory.Shell`, the `memory` tool):
  `ls`, `cat`, `grep -rn`, `sed -i`, `echo >>`, `mkdir`, `mv`, `rm`, the
  commands it was trained on, over a filesystem that is these rows
  (`Notebook.Memory.Store`). Its connection may be gone in a minute; its
  memory is not.

  Its person sees the same files, live, and corrects or removes them,
  through the same functions: what the agent believes is never hidden
  from who it works for. One file is theirs alone: `/self.md`, what they
  tell the agent to be (its instructions), which the agent reads and may
  not change.

  Paths are absolute within the memory (`"/notes/hanzo.md"`); a
  directory is there when a file is under it, or when it was made.
  """
  import Ecto.Query

  alias Notebook.Agents.Agent
  alias Notebook.Memory.File, as: MemoryFile
  alias Notebook.Repo

  @self "/self.md"
  @max_file 64 * 1024
  @max_total 1024 * 1024
  @max_files 500

  @doc "The file of the agent's instructions, its person's to write: `/self.md`."
  def self_path, do: @self

  @doc "How much an agent may keep: bytes in a file, bytes in all, and files."
  def limits, do: %{file: @max_file, total: @max_total, files: @max_files}

  @doc "Every file and directory the agent keeps, by path, `self.md` first."
  def files(agent_id) do
    rows =
      MemoryFile
      |> where(agent_id: ^agent_id)
      |> order_by(:path)
      |> Repo.all()

    [self_file(agent_id) | rows]
  end

  @doc "The files and directories under `dir` (itself not), deep: for a walk, in one query."
  def under(agent_id, dir) do
    rows =
      MemoryFile
      |> where([f], f.agent_id == ^agent_id)
      |> beneath(if dir == "/", do: "/", else: dir <> "/")
      |> order_by(:path)
      |> Repo.all()

    if dir == "/", do: [self_file(agent_id) | rows], else: rows
  end

  @doc "One file or directory, or nil."
  def get(agent_id, @self), do: self_file(agent_id)
  def get(agent_id, path), do: Repo.get_by(MemoryFile, agent_id: agent_id, path: path)

  @doc "Whether `path` is a directory: the root, one made, or one a file is under."
  def directory?(_agent_id, "/"), do: true

  def directory?(agent_id, path) do
    made = MemoryFile |> where([f], f.agent_id == ^agent_id and f.path == ^path and f.directory)
    under = MemoryFile |> where([f], f.agent_id == ^agent_id) |> beneath(path <> "/")
    Repo.exists?(made) or Repo.exists?(under)
  end

  @doc """
  Writes a file, made or replaced: `{:ok, file}`, or why not
  (`:eisdir`, `:enotdir`, `:eacces` for `self.md`, `:efbig`, `:enospc`).
  """
  def write(agent_id, path, content) when is_binary(content) do
    cond do
      path == @self -> {:error, :eacces}
      byte_size(content) > @max_file -> {:error, :efbig}
      directory?(agent_id, path) -> {:error, :eisdir}
      file_above?(agent_id, path) -> {:error, :enotdir}
      over?(agent_id, path, byte_size(content)) -> {:error, :enospc}
      true -> upsert(agent_id, path, content, false)
    end
  end

  @doc "Makes a directory (and those above it, with `parents: true`)."
  def mkdir(agent_id, path, opts \\ []) do
    cond do
      path == @self or match?(%MemoryFile{directory: false}, get(agent_id, path)) ->
        {:error, :eexist}

      directory?(agent_id, path) ->
        if opts[:parents], do: {:ok, nil}, else: {:error, :eexist}

      file_above?(agent_id, path) ->
        {:error, :enotdir}

      not opts[:parents] and not directory?(agent_id, parent(path)) ->
        {:error, :enoent}

      true ->
        upsert(agent_id, path, nil, true)
    end
  end

  @doc "Removes a file, or a directory and all under it with `recursive: true`."
  def rm(agent_id, path, opts \\ []) do
    cond do
      path == @self ->
        {:error, :eacces}

      match?(%MemoryFile{directory: false}, get(agent_id, path)) ->
        delete(agent_id, path, false)

      path != "/" and directory?(agent_id, path) ->
        if opts[:recursive], do: delete(agent_id, path, true), else: {:error, :eisdir}

      path == "/" ->
        {:error, :eacces}

      true ->
        {:error, :enoent}
    end
  end

  @doc "Changes the agent's instructions, its `self.md`: its person's to write."
  def put_instructions(%Agent{} = agent, instructions) do
    with {:ok, agent} <-
           agent |> Agent.changeset(%{"instructions" => instructions}) |> Repo.update() do
      broadcast(agent.id)
      {:ok, agent}
    end
  end

  @doc "Tells of the agent's memory as it changes: `{:memory_changed, agent_id}`."
  def subscribe(agent_id), do: Phoenix.PubSub.subscribe(Notebook.PubSub, topic(agent_id))

  defp broadcast(agent_id),
    do: Phoenix.PubSub.broadcast(Notebook.PubSub, topic(agent_id), {:memory_changed, agent_id})

  defp topic(agent_id), do: "memory:#{agent_id}"

  defp self_file(agent_id) do
    instructions = Repo.one(from a in Agent, where: a.id == ^agent_id, select: a.instructions)
    %MemoryFile{agent_id: agent_id, path: @self, content: instructions || "", directory: false}
  end

  defp upsert(agent_id, path, content, directory?) do
    now = DateTime.utc_now()

    file =
      Repo.insert!(
        %MemoryFile{agent_id: agent_id, path: path, content: content, directory: directory?},
        on_conflict: [set: [content: content, directory: directory?, updated_at: now]],
        conflict_target: [:agent_id, :path],
        returning: true
      )

    broadcast(agent_id)
    {:ok, file}
  end

  defp delete(agent_id, path, recursive?) do
    MemoryFile |> where([f], f.agent_id == ^agent_id and f.path == ^path) |> Repo.delete_all()

    if recursive?,
      do:
        MemoryFile
        |> where([f], f.agent_id == ^agent_id)
        |> beneath(path <> "/")
        |> Repo.delete_all()

    broadcast(agent_id)
    {:ok, nil}
  end

  # A file on the way to `path`: "/a.md" for "/a.md/b".
  defp file_above?(agent_id, path) do
    ancestors = ancestors(path)

    ancestors != [] and
      MemoryFile
      |> where([f], f.agent_id == ^agent_id and f.path in ^ancestors and not f.directory)
      |> Repo.exists?()
      |> Kernel.or(@self in ancestors)
  end

  defp over?(agent_id, path, bytes) do
    {count, total} =
      MemoryFile
      |> where([f], f.agent_id == ^agent_id and f.path != ^path and not f.directory)
      |> select([f], {count(f.id), coalesce(sum(fragment("length(?)", f.content)), 0)})
      |> Repo.one()

    count + 1 > @max_files or total + bytes > @max_total
  end

  defp ancestors(path) do
    case parent(path) do
      "/" -> []
      up -> [up | ancestors(up)]
    end
  end

  defp parent(path), do: path |> Path.dirname() |> then(&if(&1 == ".", do: "/", else: &1))

  # The paths under a prefix ending in "/": in byte order they lie between
  # it and the same with "0" (the character after "/") at its end, exactly
  # and with case, as LIKE would not.
  defp beneath(query, prefix) do
    upper = String.replace_suffix(prefix, "/", "0")
    where(query, [f], f.path > ^prefix and f.path < ^upper)
  end
end
