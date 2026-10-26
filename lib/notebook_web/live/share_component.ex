defmodule NotebookWeb.ShareComponent do
  @moduledoc """
  The Share dialog of a page or a folder (`Notebook.Sharing`): who has it
  through its space, the people it is shared with and their roles, a
  person to share it with, the link, made, made again or taken back, and,
  for a page, whether agents may work on it.
  A link's address shows once, when it is made: the notebook keeps only
  its hash.
  """
  use NotebookWeb, :live_component

  alias Notebook.Pages.Page
  alias Notebook.Sharing

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:link_url, fn -> nil end)
     |> assign_new(:error, fn -> nil end)
     |> load()}
  end

  defp load(socket) do
    %{scope: scope, resource: resource} = socket.assigns
    {:ok, access} = Sharing.access(scope, resource)
    assign(socket, access: access, candidates: Sharing.candidates(scope, resource))
  end

  @impl true
  # Each change of who has it is an action (Notebook.Actions), a person's
  # only, run in the page's room or the folder's space's.
  def handle_event("share", %{"user_id" => id, "role" => role}, socket) when id != "" do
    act(socket, Notebook.Actions.Share, %{user_id: String.to_integer(id), role: role})
  end

  def handle_event("share", _params, socket), do: {:noreply, socket}

  def handle_event("role", %{"user_id" => id, "role" => role}, socket) do
    handle_event("share", %{"user_id" => id, "role" => role}, socket)
  end

  def handle_event("unshare", %{"user_id" => id}, socket),
    do: act(socket, Notebook.Actions.Share, %{user_id: String.to_integer(id), role: "none"})

  def handle_event("agents", %{"agents" => agents}, socket) do
    %{scope: scope, resource: %Page{} = page} = socket.assigns
    args = %{page_id: page.id, closed: agents == "closed"}

    case NotebookWeb.Act.act(scope, Notebook.Actions.SetAgents, args) do
      {:ok, %{result: page}} ->
        send(self(), {:agents_changed, page})
        {:noreply, assign(socket, resource: page)}

      {:error, reason} ->
        {:noreply, assign(socket, error: Issho.Action.message(reason))}
    end
  end

  def handle_event("link", %{"role" => role}, socket) do
    case act_on(socket, Notebook.Actions.ShareLink, %{role: role}) do
      {:ok, %{result: url}} -> {:noreply, socket |> assign(link_url: url, error: nil) |> load()}
      {:error, reason} -> {:noreply, assign(socket, error: Issho.Action.message(reason))}
    end
  end

  defp act(socket, action, args) do
    case act_on(socket, action, args) do
      {:ok, _receipt} -> {:noreply, socket |> assign(error: nil) |> load()}
      {:error, reason} -> {:noreply, assign(socket, error: Issho.Action.message(reason))}
    end
  end

  # The action on this dialog's page or folder.
  defp act_on(socket, action, args) do
    %{scope: scope, resource: resource} = socket.assigns
    {kind, id} = kind(resource)
    NotebookWeb.Act.act(scope, action, Map.merge(args, %{kind: kind, id: id}))
  end

  defp kind(%Page{id: id}), do: {"page", id}
  defp kind(%{id: id}), do: {"folder", id}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="share-backdrop" phx-window-keydown="share_close" phx-key="Escape">
      <section
        id={@id}
        class="share-dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby={@id <> "-title"}
        phx-click-away="share_close"
      >
        <header class="share-head">
          <div>
            <p class="eyebrow">{what(@resource)}</p>
            <h2 id={@id <> "-title"}>Share {name(@resource)}</h2>
          </div>
          <button type="button" class="share-close" phx-click="share_close" aria-label="Close">
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </header>
        <p :if={@error} class="publish-error" role="alert">{@error}</p>

        <form id={@id <> "-invite"} class="share-invite" phx-submit="share" phx-target={@myself}>
          <select name="user_id" aria-label="A person" required>
            <option value="">Share with a person…</option>
            <option :for={user <- @candidates} value={user.id}>{user.name}</option>
          </select>
          <select name="role" aria-label="As">
            <option :for={role <- Sharing.roles()} value={role} selected={role == "viewer"}>
              {role_name(role)}
            </option>
          </select>
          <button type="submit" class="button button-primary">Share</button>
        </form>

        <h3>Who has it</h3>
        <ul class="share-people">
          <li class="share-space">
            <span class="share-avatar is-space"><.icon name="hero-user-group" class="size-4" /></span>
            <span :if={@space.kind == "private"} class="share-who">
              Only its owner <small>it's in a Private space</small>
            </span>
            <span :if={@space.kind != "private"} class="share-who">
              Everyone in {@space.name}
              <small>by their role in the space</small>
            </span>
          </li>
          <li :for={%{user: user, role: role} <- @access.people} id={"share-#{user.id}"}>
            <span class="share-avatar">{NotebookWeb.Layouts.initials(user.name)}</span>
            <span class="share-who">{user.name}<small>{user.email}</small></span>
            <form id={"#{@id}-role-#{user.id}"} phx-change="role" phx-target={@myself}>
              <input type="hidden" name="user_id" value={user.id} />
              <select name="role" aria-label={"#{user.name}'s role"}>
                <option :for={r <- Sharing.roles()} value={r} selected={r == role}>
                  {role_name(r)}
                </option>
              </select>
            </form>
            <button
              type="button"
              class="share-remove"
              phx-click="unshare"
              phx-value-user_id={user.id}
              phx-target={@myself}
              aria-label={"Stop sharing with #{user.name}"}
              title="Stop sharing"
            >
              <.icon name="hero-x-mark" class="size-4" />
            </button>
          </li>
        </ul>

        <h3>Anyone with the link</h3>
        <form id={@id <> "-link"} class="share-link" phx-change="link" phx-target={@myself}>
          <span class="share-avatar is-link"><.icon name="hero-link" class="size-4" /></span>
          <span class="share-who">
            {if @access.link, do: "On", else: "Off"}
            <small>{link_hint(@access.link, @resource)}</small>
          </span>
          <select name="role" aria-label="What the link gives">
            <option value="off" selected={is_nil(@access.link)}>No link</option>
            <option :for={r <- Sharing.link_roles(@resource)} value={r} selected={r == @access.link}>
              {role_name(r)}
            </option>
          </select>
        </form>
        <div :if={@link_url} class="share-url">
          <input id={@id <> "-url"} type="text" value={@link_url} readonly aria-label="The link" />
          <button
            type="button"
            class="button"
            phx-click={JS.dispatch("notebook:copy", to: "##{@id}-url")}
          >
            Copy
          </button>
          <p>Copy it now: it shows once. Choosing again makes a new link, and the last one stops.</p>
        </div>
        <p :if={@access.link && is_nil(@link_url)} class="share-note">
          A link is on. Choose its role again to make a new one, and the last one stops.
        </p>

        <%= if match?(%Page{}, @resource) do %>
          <h3>Agents</h3>
          <form
            id={@id <> "-agents"}
            class="share-agents"
            phx-change="agents"
            phx-target={@myself}
          >
            <span class={["share-avatar is-agent", closed?(@resource) && "is-closed"]}>
              <.icon
                name={if closed?(@resource), do: "hero-no-symbol", else: "hero-sparkles"}
                class="size-4"
              />
            </span>
            <span class="share-who">
              {if closed?(@resource), do: "Off limits", else: "May work here"}
              <small>{agents_hint(@resource)}</small>
            </span>
            <select
              name="agents"
              aria-label="Whether agents may work on this page"
              disabled={space_closed?(@resource)}
            >
              <option value="open" selected={not @resource.closed_to_agents}>May work here</option>
              <option value="closed" selected={@resource.closed_to_agents}>Off limits</option>
            </select>
          </form>
        <% end %>
      </section>
    </div>
    """
  end

  defp what(%Page{}), do: "Page"
  defp what(_folder), do: "Folder"

  defp name(%Page{title: title}), do: title
  defp name(folder), do: folder.name

  defp role_name("viewer"), do: "Can read"
  defp role_name("commenter"), do: "Can comment"
  defp role_name("editor"), do: "Can edit"

  defp closed?(page), do: Notebook.Pages.closed_to_agents?(page)
  defp space_closed?(page), do: Notebook.Repo.preload(page, :space).space.closed_to_agents

  defp agents_hint(page) do
    cond do
      space_closed?(page) -> "Its space is off limits to agents."
      page.closed_to_agents -> "No agent reads it, finds it or joins it."
      true -> "Its people's agents may do what they may."
    end
  end

  defp link_hint(nil, _resource), do: "Only the people above have it."
  defp link_hint(_role, %Page{}), do: "Anyone signed in with the link opens this page."
  defp link_hint(_role, _folder), do: "Anyone signed in with the link opens its pages."
end
