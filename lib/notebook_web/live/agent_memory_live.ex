defmodule NotebookWeb.AgentMemoryLive do
  @moduledoc """
  An agent's memory, for its person (`Notebook.Memory`): what they tell
  it to be (its `self.md`), and the files it keeps, as it writes them,
  to read, correct or remove, through the same functions the agent's
  bash goes through.
  """
  use NotebookWeb, :live_view

  alias Notebook.Agents.Agent
  alias Notebook.Memory

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_scope.user

    case Notebook.Repo.get_by(Agent, id: id, user_id: user.id) do
      %Agent{revoked_at: nil} = agent ->
        if connected?(socket), do: Memory.subscribe(agent.id)

        {:ok,
         socket
         |> assign(
           page_title: "#{agent.name}'s memory",
           agent: agent,
           draft: nil,
           outdated?: false
         )
         |> load()}

      _other ->
        {:ok,
         socket
         |> put_flash(:error, "There is no such agent of yours.")
         |> push_navigate(to: ~p"/agents")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    path = params["file"] || Memory.self_path()
    {:noreply, socket |> assign(path: path, draft: nil, outdated?: false) |> load()}
  end

  defp load(socket) do
    %{agent: agent} = socket.assigns
    files = Memory.files(agent.id)
    path = socket.assigns[:path] || Memory.self_path()
    file = Enum.find(files, &(&1.path == path and not &1.directory))
    assign(socket, files: files, file: file)
  end

  @impl true
  def handle_event("edit", %{"content" => content}, socket),
    do: {:noreply, assign(socket, draft: content)}

  def handle_event("save", %{"content" => content}, socket) do
    %{agent: agent, path: path} = socket.assigns

    result =
      if path == Memory.self_path(),
        do: with({:ok, agent} <- Memory.put_instructions(agent, content), do: {:ok, agent}),
        else: Memory.write(agent.id, path, content)

    case result do
      {:ok, %Agent{} = agent} ->
        {:noreply,
         socket
         |> assign(agent: agent, draft: nil, outdated?: false)
         |> load()
         |> put_flash(:info, "Saved.")}

      {:ok, _file} ->
        {:noreply,
         socket |> assign(draft: nil, outdated?: false) |> load() |> put_flash(:info, "Saved.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, refusal(reason))}
    end
  end

  def handle_event("new", %{"path" => path}, socket) do
    path = "/" <> (path |> String.trim() |> String.trim_leading("/"))

    case Memory.write(socket.assigns.agent.id, path, "") do
      {:ok, _file} ->
        {:noreply, push_patch(socket, to: ~p"/agents/#{socket.assigns.agent.id}?file=#{path}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, refusal(reason))}
    end
  end

  def handle_event("remove", _params, socket) do
    %{agent: agent, path: path} = socket.assigns
    {:ok, _} = Memory.rm(agent.id, path)

    {:noreply,
     socket
     |> put_flash(:info, "#{path} is gone from #{agent.name}'s memory.")
     |> push_patch(to: ~p"/agents/#{agent.id}")}
  end

  # The agent writes as the person reads: the tree follows; the file open
  # follows too, unless the person is changing it.
  @impl true
  def handle_info({:memory_changed, _id}, socket) do
    socket =
      if socket.assigns.path == Memory.self_path(),
        do: assign(socket, agent: Notebook.Repo.reload(socket.assigns.agent)),
        else: socket

    if socket.assigns.draft,
      do: {:noreply, socket |> assign(outdated?: true) |> load_tree()},
      else: {:noreply, load(socket)}
  end

  defp load_tree(socket), do: assign(socket, files: Memory.files(socket.assigns.agent.id))

  defp refusal(:eisdir), do: "That is a directory."
  defp refusal(:enotdir), do: "A file is on the way to that path."
  defp refusal(:efbig), do: "A memory file holds at most 64 KB."
  defp refusal(:enospc), do: "The memory is full: remove something first."
  defp refusal(:eacces), do: "That file is written from its own place."
  defp refusal(%Ecto.Changeset{}), do: "The instructions are too long (8,000 characters at most)."
  defp refusal(other), do: "Not saved: #{inspect(other)}."

  @impl true
  def render(assigns) do
    ~H"""
    <div class="notebook-shell">
      <main class="notebook-main">
        <div class="page-view agents-page memory-page">
          <div class="page-nav">
            <.link navigate={~p"/agents"}>← Your agents</.link>
            <span>MEMORY</span>
          </div>
          <div class="page-heading">
            <p class="eyebrow">{@agent.name}</p>
            <h1>What it remembers</h1>
            <p>
              Files it keeps between its sessions, read and written with a bash of its own. It reads
              <code>self.md</code>
              first: what you tell it to be. Correct a note, or remove it, and it
              reads the change next time.
            </p>
          </div>
          <Layouts.flash_group flash={@flash} />

          <div class="memory-layout">
            <nav class="memory-tree" aria-label="Its memory" id="memory-tree">
              <.link
                :for={file <- @files}
                patch={if file.directory, do: nil, else: ~p"/agents/#{@agent.id}?file=#{file.path}"}
                class={[
                  "memory-entry",
                  file.directory && "is-dir",
                  file.path == @path && "is-current",
                  file.path == Memory.self_path() && "is-self"
                ]}
                style={"padding-left: #{10 + depth(file.path) * 16}px"}
              >
                <.icon
                  name={
                    cond do
                      file.path == Memory.self_path() -> "hero-user-circle"
                      file.directory -> "hero-folder"
                      true -> "hero-document-text"
                    end
                  }
                  class="size-4"
                />
                <span>{Path.basename(file.path)}</span>
                <small :if={not file.directory}>{size(file.content)}</small>
              </.link>
              <p :if={length(@files) == 1} class="memory-empty">Nothing noted yet.</p>
              <form phx-submit="new" class="memory-new">
                <input name="path" placeholder="people/hanzo.md" aria-label="A new file's path" />
                <button type="submit" class="button">New</button>
              </form>
            </nav>

            <section :if={@file} class="memory-file" id="memory-file">
              <header>
                <strong><code>/memories{@file.path}</code></strong>
                <small :if={@file.path == Memory.self_path()}>What you tell it to be: yours to write, its to read.</small>
                <small :if={@file.path != Memory.self_path() and @file.updated_at}>
                  Written {Calendar.strftime(@file.updated_at, "%-d %b, %H:%M")}
                </small>
              </header>
              <p :if={@outdated?} class="memory-outdated">
                {@agent.name} changed this file while you were editing. Save yours, or <.link patch={
                  ~p"/agents/#{@agent.id}?file=#{@path}"
                }>read its version</.link>.
              </p>
              <form phx-change="edit" phx-submit="save" id="memory-form">
                <textarea name="content" rows="18" spellcheck="false" aria-label="The file">{@draft || @file.content}</textarea>
                <div class="memory-actions">
                  <button type="submit" class="button button-primary">Save</button>
                  <button
                    :if={@file.path != Memory.self_path()}
                    type="button"
                    class="agent-revoke"
                    phx-click="remove"
                    data-confirm={"Remove #{@file.path} from #{@agent.name}'s memory?"}
                  >
                    Remove
                  </button>
                </div>
              </form>
            </section>
          </div>
        </div>
      </main>
    </div>
    """
  end

  defp depth(path), do: path |> String.split("/", trim: true) |> length() |> Kernel.-(1)

  defp size(nil), do: ""
  defp size(content) when byte_size(content) < 1024, do: "#{byte_size(content)} B"
  defp size(content), do: "#{Float.round(byte_size(content) / 1024, 1)} KB"
end
