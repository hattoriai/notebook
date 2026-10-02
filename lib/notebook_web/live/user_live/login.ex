defmodule NotebookWeb.UserLive.Login do
  use NotebookWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    {:ok, assign(socket, form: to_form(%{"email" => email}, as: "user"))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="auth-page">
      <div class="auth-intro">
        <p class="eyebrow">Welcome back</p><h1>Pick up where<br />you left off.</h1><p>
          Your pages are waiting.
        </p>
      </div>
      <section class="auth-panel" aria-labelledby="login-title">
        <p class="eyebrow">Notebook</p><h2 id="login-title">Log in</h2>
        <p>New here? <.link navigate={~p"/users/register"}>Create an account</.link></p>
        <.form for={@form} id="login_form_password" action={~p"/users/log-in"}>
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
