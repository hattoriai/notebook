defmodule NotebookWeb.AgentsLive do
  @moduledoc """
  Connect an agent: the person's token, and the command that connects
  Claude Code or Codex to the Notebook with it. The agent then works in
  the pages on the person's behalf, seen by everyone on them.
  """
  use NotebookWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    url = NotebookWeb.Endpoint.url() <> "/mcp?token=" <> NotebookWeb.AgentAuth.token(user)
    {:ok, assign(socket, page_title: "Connect an agent", url: url)}
  end

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
            <p class="eyebrow">Work with an agent</p>
            <h1>Connect an agent</h1>
            <p>
              Your agent works in the pages on your behalf: everyone on a page sees it there,
              its cursor in a text, its pointer on a board, its cell in a table, and its changes as it makes them.
            </p>
          </div>

          <section class="agent-step">
            <h2>Claude Code</h2>
            <pre id="claude-command"><code>claude mcp add --transport http notebook "{@url}"</code></pre>
          </section>

          <section class="agent-step">
            <h2>Codex</h2>
            <pre id="codex-command"><code>codex mcp add notebook --url "{@url}"</code></pre>
            <p>Or in <code>~/.codex/config.toml</code>:</p>
            <pre><code>{"[mcp_servers.notebook]\nurl = \"#{@url}\""}</code></pre>
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
            </ul>
            <p>Open the page in your browser first, to watch it work.</p>
          </section>

          <p class="agent-note">
            This address holds your token: whoever has it can act as you in the Notebook.
          </p>
        </div>
      </main>
    </div>
    """
  end
end
