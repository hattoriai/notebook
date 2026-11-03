defmodule NotebookWeb.MCP.Consent do
  @moduledoc """
  The page where a person lets an MCP client (Claude Code, Codex) work in
  the Notebook for them, with OAuth, and the page of an authorization
  that went wrong: in the Notebook's look (`Sake.Auth.Consent`).

  An approved client acts as one of the person's agents at a time, or a
  bot of the notebook's for an admin (`NotebookWeb.MCP.Actors`): never as
  the person themselves.
  """
  @behaviour Sake.Auth.Consent

  use NotebookWeb, :html

  @impl true
  def render(assigns),
    do:
      assigns |> Map.put_new(:user_code, nil) |> consent() |> page("Allow #{assigns.client_name}")

  @impl true
  def render_error(assigns), do: assigns |> error() |> page(assigns.title)

  # The Notebook's root layout, with only its wordmark: Sake renders this
  # page outside the app's pages, and the person is signed in.
  defp page(inner, title) do
    %{inner_content: inner, page_title: title, current_scope: nil, bare: true}
    |> NotebookWeb.Layouts.root()
    |> Phoenix.HTML.Safe.to_iodata()
  end

  defp consent(assigns) do
    ~H"""
    <main class="auth-page" id="consent">
      <div class="auth-intro">
        <p class="eyebrow">Connect your agents</p>
        <h1>Work here<br />with {@client_name}.</h1>
        <p>
          It joins your pages as one of your agents, by its name, with its persona and its memory.
        </p>
      </div>
      <section class="auth-panel" aria-labelledby="consent-title">
        <p class="eyebrow">Allow access</p>
        <h2 id="consent-title">Allow {@client_name}?</h2>
        <p>
          {@client_name} asks to work in the Notebook for you, <strong>{@subject_display}</strong>.
        </p>
        <p :if={@user_code} class="consent-note">
          Check that your device shows the code <code>{@user_code}</code>.
        </p>
        <ul class="consent-list" id="consent-scopes">
          <li>It acts as one of your agents at a time. You or it choose which, as you work.</li>
          <li>If you are an admin, it can act as the notebook's bots too.</li>
          <li>It never acts as you, and sees only what you may see.</li>
          <li>To stop it acting as an agent, revoke that agent on your Agents page.</li>
        </ul>
        <p :if={@redirect_host && @loopback?} class="consent-note consent-warn" role="status">
          The code goes to an app on this computer, at {@redirect_host}. Go on only if you
          started this from an app you trust.
        </p>
        <p :if={@redirect_host && !@loopback?} class="consent-note">
          The Notebook then sends you back to {@redirect_host}.
        </p>
        <form method="post" action={@action} class="consent-actions" id="consent-form">
          <input type="hidden" name="request" value={@request} />
          <input :if={@csrf_token != ""} type="hidden" name="_csrf_token" value={@csrf_token} />
          <button type="submit" name="decision" value="deny" class="button">Deny</button>
          <button type="submit" name="decision" value="approve" class="button button-primary">
            Allow <span aria-hidden="true">↗</span>
          </button>
        </form>
        <p class="consent-resource">For {@resource}</p>
      </section>
    </main>
    """
  end

  defp error(assigns) do
    ~H"""
    <main class="auth-page" id="consent-error">
      <div class="auth-intro">
        <p class="eyebrow">Connect your agents</p>
        <h1>{@title}</h1>
      </div>
      <section class="auth-panel">
        <p>{@message}</p>
        <.link href={~p"/agents"} class="button button-primary">Back to your agents</.link>
      </section>
    </main>
    """
  end
end
