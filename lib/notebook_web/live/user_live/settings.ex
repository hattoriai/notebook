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
       page_title: title(socket.assigns.live_action),
       trigger_submit: false
     )}
  end

  defp title(:profile), do: "Profile · Account settings"
  defp title(:password), do: "Password · Account settings"
  defp title(:notifications), do: "Notifications · Account settings"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.settings area={:account} current={@live_action} flash={@flash} jumon={@jumon}>
      <div class="settings-grid">
        <section :if={@live_action == :profile} id="profile-name">
          <h2>Display name</h2>
          <p>It appears beside your cursor, and in @mentions.</p>
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
        <section :if={@live_action == :profile} id="profile-handle">
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
        <section :if={@live_action == :password} id="password">
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
        <section :if={@live_action == :notifications} class="settings-wide" id="notifications-prefs">
          <h2>Notifications</h2>
          <p>
            What you hear of, in your Inbox and by email. An email waits ten minutes,
            and doesn't go if you read the notification first.
          </p>
          <Chime.Components.preferences id="notifications" chime={@chime}>
            <:setting :let={control}>
              <Erabi.Components.select
                id={control.id}
                name={control.name}
                value={control.value}
                options={control.options}
                label={control.label}
                disabled={control.disabled}
                clearable={false}
                class="is-compact"
              />
            </:setting>
          </Chime.Components.preferences>
        </section>
      </div>
    </Layouts.settings>
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
