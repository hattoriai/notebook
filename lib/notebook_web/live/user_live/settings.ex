defmodule NotebookWeb.UserLive.Settings do
  use NotebookWeb, :live_view
  on_mount {NotebookWeb.UserAuth, :require_authenticated}
  alias Notebook.Accounts

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    {:ok,
     assign(socket,
       name_form: to_form(Accounts.change_user_name(user)),
       handle_form: to_form(Accounts.change_user_handle(user)),
       password_form: to_form(Accounts.change_user_password(user, %{}, hash_password: false)),
       current_email: user.email,
       trigger_submit: false
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="settings-page">
      <div class="page-nav"><.link navigate={~p"/"}>← Back to pages</.link><span>ACCOUNT</span></div>
      <div class="page-heading">
        <p class="eyebrow">Your account</p><h1>Settings</h1><p>
          Your name appears beside your cursor and in @mentions.
        </p>
      </div>
      <Layouts.flash_group flash={@flash} />
      <div class="settings-grid">
        <section>
          <h2>Display name</h2><p>Let your collaborators know who is writing.</p>
          <.form
            for={@name_form}
            id="name_form"
            phx-change="validate_name"
            phx-submit="update_name"
            class="settings-form"
          >
            <.input field={@name_form[:name]} type="text" label="Name" autocomplete="name" required />
            <button class="button button-primary" type="submit">Save name</button>
          </.form>
        </section>
        <section>
          <h2>Handle</h2>
          <p>
            The address of the pages you publish: <strong>{handle_example(@current_scope.user)}</strong>.
            Change it, and their addresses change with it.
          </p>
          <.form
            for={@handle_form}
            id="handle_form"
            phx-change="validate_handle"
            phx-submit="update_handle"
            class="settings-form"
          >
            <.input
              field={@handle_form[:handle]}
              type="text"
              label="Handle"
              autocomplete="off"
              required
            />
            <button class="button button-primary" type="submit">Save handle</button>
          </.form>
        </section>
        <section>
          <h2>Password</h2><p>Use at least 12 characters.</p>
          <.form
            for={@password_form}
            id="password_form"
            action={~p"/users/update-password"}
            phx-change="validate_password"
            phx-submit="update_password"
            phx-trigger-action={@trigger_submit}
            class="settings-form"
          >
            <input name={@password_form[:email].name} type="hidden" value={@current_email} />
            <.input
              field={@password_form[:password]}
              type="password"
              label="New password"
              autocomplete="new-password"
              required
            />
            <.input
              field={@password_form[:password_confirmation]}
              type="password"
              label="Confirm password"
              autocomplete="new-password"
              required
            />
            <button class="button button-primary" type="submit">Save password</button>
          </.form>
        </section>
        <section class="settings-wide">
          <h2>Notifications</h2>
          <p>
            What you hear of, in your Inbox and by email. An email waits ten minutes,
            and doesn't go if you read the notification first.
          </p>
          <Chime.Components.preferences id="notifications" chime={@chime} />
        </section>
      </div>
    </main>
    """
  end

  @impl true
  def handle_event("validate_name", %{"user" => params}, socket) do
    form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_name(params)
      |> to_form(action: :validate)

    {:noreply, assign(socket, name_form: form)}
  end

  def handle_event("update_name", %{"user" => params}, socket) do
    case Accounts.update_user_name(socket.assigns.current_scope.user, params) do
      {:ok, user} ->
        scope = %{socket.assigns.current_scope | user: user}

        {:noreply,
         socket
         |> assign(current_scope: scope, name_form: to_form(Accounts.change_user_name(user)))
         |> put_flash(:info, "Name saved")}

      {:error, changeset} ->
        {:noreply, assign(socket, name_form: to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_handle", %{"user" => params}, socket) do
    form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_handle(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, handle_form: form)}
  end

  def handle_event("update_handle", %{"user" => params}, socket) do
    case Accounts.update_user_handle(socket.assigns.current_scope.user, params) do
      {:ok, user} ->
        scope = %{socket.assigns.current_scope | user: user}

        {:noreply,
         socket
         |> assign(current_scope: scope, handle_form: to_form(Accounts.change_user_handle(user)))
         |> put_flash(:info, "Handle saved")}

      {:error, changeset} ->
        {:noreply, assign(socket, handle_form: to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_password", %{"user" => params}, socket) do
    form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(params, hash_password: false)
      |> to_form(action: :validate)

    {:noreply, assign(socket, password_form: form)}
  end

  def handle_event("update_password", %{"user" => params}, socket) do
    case Accounts.change_user_password(socket.assigns.current_scope.user, params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end

  # Where the person's published pages are read.
  defp handle_example(user) do
    %{url: url, prefix: prefix, paths: paths} = Notebook.Publishing.config()
    host = URI.parse(url).host
    if paths == :people, do: "#{host}#{prefix}/#{user.handle}/…", else: "#{host}#{prefix}/…"
  end
end
