defmodule NotebookWeb.AgentsLive do
  @moduledoc """
  A person's agents (`Notebook.Agents`): each one connected with its own
  name and token, which can expire and be revoked, seen in the pages by
  its name. Connecting one shows its token once, and the commands that
  connect Claude Code or Codex with it.
  """
  use NotebookWeb, :live_view

  alias Notebook.Agents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Your agents", connected: nil)
     |> assign_agents()
     |> assign_form(Agents.change(%{"name" => default_name(socket), "lifetime" => "90"}))}
  end

  defp assign_agents(socket),
    do: assign(socket, agents: Agents.list(socket.assigns.current_scope))

  defp assign_form(socket, changeset), do: assign(socket, form: to_form(changeset, as: :agent))

  # Names are written in many orders: the whole one, not a guess at a first name.
  defp default_name(socket), do: "#{socket.assigns.current_scope.user.name}'s agent"

  @impl true
  def handle_event("validate", %{"agent" => params}, socket),
    do: {:noreply, assign_form(socket, params |> Agents.change() |> Map.put(:action, :validate))}

  def handle_event("connect", %{"agent" => params}, socket) do
    case Agents.create(socket.assigns.current_scope, params) do
      {:ok, agent, token} ->
        {:noreply,
         socket
         |> assign(
           connected: %{agent: agent, url: NotebookWeb.Endpoint.url() <> "/mcp?token=" <> token}
         )
         |> assign_agents()
         |> assign_form(Agents.change(%{"name" => default_name(socket), "lifetime" => "90"}))}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("revoke", %{"id" => id}, socket) do
    case Agents.revoke(socket.assigns.current_scope, id) do
      {:ok, agent} ->
        connected = socket.assigns.connected

        {:noreply,
         socket
         |> assign(
           connected: if(connected && connected.agent.id == agent.id, do: nil, else: connected)
         )
         |> assign_agents()
         |> put_flash(:info, "#{agent.name} is revoked: its token works no more.")}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  def handle_event("done", _params, socket), do: {:noreply, assign(socket, connected: nil)}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="notebook-shell">
      <main class="notebook-main">
        <div class="page-view agents-page">
          <div class="page-nav">
            <.link navigate={~p"/"}>← All pages</.link>
            <span>AGENTS</span>
          </div>
          <div class="page-heading">
            <p class="eyebrow">Work with agents</p>
            <h1>Your agents</h1>
            <p>
              An agent works in the pages on your behalf, by the name you give it: everyone on a page
              sees it there, its cursor in a text, its pointer on a board, its cell in a table, and its
              changes as it makes them. It may do what you may, and you can pause or stop it.
            </p>
          </div>
          <Layouts.flash_group flash={@flash} />

          <section :if={@connected} class="agent-connected" id="agent-connected">
            <div class="agent-connected-head">
              <.icon name="hero-check-circle" class="size-5" />
              <div>
                <strong>{@connected.agent.name} is connected</strong>
                <p>Copy its address now: it holds the agent's token, which is not shown again.</p>
              </div>
            </div>
            <div class="agent-address">
              <input
                id="agent-url"
                type="text"
                readonly
                value={@connected.url}
                aria-label="The agent's address"
              />
              <button
                type="button"
                class="button"
                phx-click={JS.dispatch("notebook:copy", to: "#agent-url")}
              >
                Copy
              </button>
            </div>
            <div class="agent-step">
              <h2>Claude Code</h2>
              <pre id="claude-command"><code>claude mcp add --transport http notebook "{@connected.url}"</code></pre>
            </div>
            <div class="agent-step">
              <h2>Codex</h2>
              <pre id="codex-command"><code>codex mcp add notebook --url "{@connected.url}"</code></pre>
            </div>
            <button type="button" class="agent-done" phx-click="done">Done, I copied it</button>
          </section>

          <section class="agent-list" id="agent-list">
            <h2>Connected</h2>
            <p :if={@agents == []} class="agent-empty">No agent yet. Connect one below.</p>
            <ul :if={@agents != []}>
              <li
                :for={agent <- @agents}
                id={"agent-#{agent.id}"}
                class={[ended?(agent) && "is-ended"]}
              >
                <span class="agent-avatar" aria-hidden="true"><.icon
                  name="hero-sparkles"
                  class="size-4"
                /></span>
                <div class="agent-who">
                  <strong>{agent.name}</strong>
                  <small>
                    <code>{agent.token_hint}…</code>
                    · connected {date(agent.inserted_at)} · {seen(agent)} · {ends(agent)}
                  </small>
                </div>
                <.link navigate={~p"/agents/#{agent.id}"} class="agent-memory-link">
                  <.icon name="hero-book-open" class="size-4" /> Memory
                </.link>
                <button
                  type="button"
                  class="agent-revoke"
                  phx-click="revoke"
                  phx-value-id={agent.id}
                  data-confirm={"Revoke #{agent.name}? Its token stops working at once."}
                >
                  Revoke
                </button>
              </li>
            </ul>
          </section>

          <section class="agent-new" id="agent-new">
            <h2>Connect an agent</h2>
            <.form
              for={@form}
              id="agent-form"
              phx-change="validate"
              phx-submit="connect"
              class="agent-form"
            >
              <.input
                field={@form[:name]}
                type="text"
                label="Its name, as people see it"
                autocomplete="off"
              />
              <.input
                field={@form[:lifetime]}
                type="select"
                label="Its token lasts"
                options={Agents.lifetimes()}
                value={@form.params["lifetime"] || "90"}
              />
              <button type="submit" class="button button-primary">Connect</button>
            </.form>
          </section>

          <section class="agent-step">
            <h2>Then ask</h2>
            <ul class="agent-prompts">
              <li>
                “Open the board <em>The forge, planned</em>, add a note for each step of forging a blade, and join them in order.”
              </li>
              <li>
                “In <em>Blades in progress</em>, give every task without an owner to Masamune, and mark the folded steel done.”
              </li>
              <li>“Read <em>A tour of Notebook</em> and add a short summary at the top, in bold.”</li>
              <li>
                Select some words in a page, then: “Rewrite what I have selected in <em>A tour of Notebook</em>, plainer.”
              </li>
            </ul>
            <p>Open the page in your browser first, to watch it work.</p>
          </section>
        </div>
      </main>
    </div>
    """
  end

  defp ended?(agent),
    do: agent.expires_at && DateTime.before?(agent.expires_at, DateTime.utc_now())

  defp date(at), do: Calendar.strftime(at, "%-d %b %Y")

  defp seen(%{last_seen_at: nil}), do: "not seen yet"
  defp seen(%{last_seen_at: at}), do: "last seen " <> Calendar.strftime(at, "%-d %b, %H:%M")

  defp ends(%{expires_at: nil}), do: "no end"

  defp ends(agent),
    do:
      if(ended?(agent),
        do: "ended #{date(agent.expires_at)}",
        else: "ends #{date(agent.expires_at)}"
      )
end
