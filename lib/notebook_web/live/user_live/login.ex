defmodule NotebookWeb.UserLive.Login do
  use NotebookWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    oidc = Notebook.OIDC.config()

    {:ok,
     assign(socket,
       form: to_form(%{"email" => email}, as: "user"),
       invite_only: Notebook.Invitations.invite_only?(),
       oidc: oidc
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="auth-page">
      <div class="auth-intro">
        <p class="eyebrow">Welcome back</p><h1>Pick up where<br />you left off.</h1><p>
          Your pages are waiting.
        </p>
        <a class="hattori-mark" href="https://hattori.ai/">Hattori AI</a>
      </div>
      <section class="auth-panel" aria-labelledby="login-title">
        <p class="eyebrow">Notebook</p><h2 id="login-title">Log in</h2>
        <p :if={not @invite_only or @oidc.auto_register}>
          New here? <.link navigate={~p"/users/register"}>Create an account</.link>
        </p>
        <p :if={@invite_only and not @oidc.auto_register}>
          New here? Ask an admin of this notebook for an invitation.
        </p>

        <div :if={@oidc.enabled} class="mb-4">
          <.link
            id="sso-login"
            href={~p"/users/oidc"}
            class="button button-primary w-full justify-center"
          >
            Log in with {@oidc.name} <span aria-hidden="true">↗</span>
          </.link>
        </div>

        <p :if={@oidc.enabled and @oidc.password_login} class="text-xs text-center my-4 opacity-60">
          or with an email and password
        </p>

        <.form
          :if={not @oidc.enabled or @oidc.password_login}
          for={@form}
          id="login_form_password"
          action={~p"/users/log-in"}
        >
          <.input field={@form[:email]} type="email" label="Email" autocomplete="email" required />
          <.input
            field={@form[:password]}
            type="password"
            label="Password"
            autocomplete="current-password"
            required
          />
          <button
            class="button button-primary"
            type="submit"
            name={@form[:remember_me].name}
            value="true"
          >Log in <span aria-hidden="true">↗</span></button>
        </.form>
      </section>
    </main>
    """
  end
end
