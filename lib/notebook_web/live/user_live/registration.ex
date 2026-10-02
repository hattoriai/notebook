defmodule NotebookWeb.UserLive.Registration do
  use NotebookWeb, :live_view
  alias Notebook.Accounts
  alias Notebook.Accounts.User

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user), do: {:ok, redirect(socket, to: ~p"/")}

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       form: to_form(Accounts.change_user_registration(%User{}, %{}, validate_unique: false))
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="auth-page">
      <div class="auth-intro">
        <p class="eyebrow">Your space starts here</p><h1>Make room for<br />your ideas.</h1><p>
          A shared notebook for words, images, files, and people.
        </p>
      </div>
      <section class="auth-panel" aria-labelledby="register-title">
        <p class="eyebrow">Join Notebook</p><h2 id="register-title">Create your account</h2>
        <p>Already here? <.link navigate={~p"/users/log-in"}>Log in</.link></p>
        <.form for={@form} id="registration_form" action={~p"/users/register"} phx-change="validate">
          <.input field={@form[:name]} type="text" label="Your name" autocomplete="name" required />
          <.input field={@form[:email]} type="email" label="Email" autocomplete="email" required />
          <.input
            field={@form[:password]}
            type="password"
            label="Password"
            autocomplete="new-password"
            minlength="12"
            required
          />
          <button class="button button-primary" type="submit">Create account
          <span aria-hidden="true">↗</span></button>
        </.form>
      </section>
    </main>
    """
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    changeset =
      Accounts.change_user_registration(%User{}, params,
        validate_unique: false,
        hash_password: false
      )

    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end
end
