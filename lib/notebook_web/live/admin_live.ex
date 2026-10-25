defmodule NotebookWeb.AdminLive do
  @moduledoc """
  The notebook's own settings, for its admins: where its files are kept
  (`Notebook.Storage`), on this server or in a bucket, and the copy of
  the files from one to the other.
  """
  use NotebookWeb, :live_view

  alias Notebook.Accounts.Scope
  alias Notebook.Storage

  @impl true
  def mount(_params, _session, socket) do
    if Scope.admin?(socket.assigns.current_scope) do
      if connected?(socket), do: Storage.subscribe()
      config = Storage.config()

      {:ok,
       socket
       |> assign(page_title: "Notebook settings", config: config, copying: nil)
       |> assign_form(Storage.change(config))
       |> assign_other()}
    else
      {:ok,
       socket
       |> put_flash(:error, "Only the notebook's admins change its settings.")
       |> push_navigate(to: ~p"/")}
    end
  end

  defp assign_form(socket, changeset) do
    assign(socket,
      form: to_form(changeset, as: :storage),
      kind: Ecto.Changeset.get_field(changeset, :kind),
      provider: provider(Ecto.Changeset.get_field(changeset, :provider))
    )
  end

  defp assign_other(socket) do
    other = if Storage.other_files?(), do: Storage.other()
    assign(socket, other: other, last_copy: Storage.last_copy(), removing: false)
  end

  defp provider(id), do: Enum.find(Storage.providers(), &(&1.id == id)) || hd(Storage.providers())

  @impl true
  def handle_event("validate", %{"storage" => params}, socket) do
    params = fill_region(params, socket.assigns.provider)
    changeset = socket.assigns.config |> Storage.change(params) |> Map.put(:action, :validate)
    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"storage" => params}, socket) do
    case Storage.save(socket.assigns.current_scope, params) do
      {:ok, config} ->
        {:noreply,
         socket
         |> assign(config: config)
         |> assign_form(Storage.change(config))
         |> assign_other()
         |> put_flash(:info, saved(config))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "Only the notebook's admins change its settings.")}
    end
  end

  def handle_event("copy", _params, socket) do
    case Storage.copy(socket.assigns.current_scope) do
      {:ok, _job} -> {:noreply, assign(socket, copying: 0)}
      {:error, _reason} -> {:noreply, put_flash(socket, :error, "There is nothing to copy.")}
    end
  end

  def handle_event("prune", _params, socket) do
    case Storage.prune(socket.assigns.current_scope) do
      {:ok, _job} -> {:noreply, assign(socket, removing: true)}
      {:error, _reason} -> {:noreply, put_flash(socket, :error, "There is nothing to remove.")}
    end
  end

  @impl true
  def handle_info({:storage, :pruned, n}, socket) do
    {:noreply,
     socket
     |> assign_other()
     |> put_flash(
       :info,
       "#{n} #{if n == 1, do: "file", else: "files"} removed, now that the store has them."
     )}
  end

  def handle_info({:storage, :copying, n}, socket), do: {:noreply, assign(socket, copying: n)}

  def handle_info({:storage, :copied, _result}, socket),
    do: {:noreply, socket |> assign(copying: nil) |> assign_other()}

  def handle_info({:storage, :saved}, socket) do
    config = Storage.config()
    {:noreply, socket |> assign(config: config) |> assign_other()}
  end

  # A store chosen with no region yet: its own.
  defp fill_region(%{"provider" => id} = params, previous) do
    region = params["region"] || ""

    if id != previous.id and (region == "" or region == previous.region),
      do: Map.put(params, "region", provider(id).region),
      else: params
  end

  defp fill_region(params, _previous), do: params

  defp saved(%{kind: "bucket", bucket: bucket}),
    do: "New files go to the bucket #{bucket} now."

  defp saved(_config), do: "New files are kept on this server now."

  @impl true
  def render(assigns) do
    ~H"""
    <main class="settings-page admin-page">
      <div class="page-nav"><.link navigate={~p"/"}>← Back to pages</.link><span>NOTEBOOK</span></div>
      <div class="page-heading">
        <p class="eyebrow">This notebook</p>
        <h1>Notebook settings</h1>
        <p>What is the whole notebook's, for everyone in it. Only its admins see this.</p>
      </div>
      <Layouts.flash_group flash={@flash} />

      <div class="settings-grid">
        <section class="settings-wide" id="storage">
          <h2>Where files are kept</h2>
          <p>
            The images and attachments of the pages. Keep them on this server, or in a bucket
            that speaks S3: a server's disk fills up, and on Fly.io or a container it may not last.
            The pages keep their files' addresses wherever the files are.
          </p>

          <div class={["storage-now", @config.kind == "bucket" && "is-bucket"]}>
            <.icon
              name={if @config.kind == "bucket", do: "hero-cloud", else: "hero-server"}
              class="size-5"
            />
            <div :if={@config.kind == "bucket"}>
              <strong>In the bucket {@config.bucket}</strong>
              <small>{provider(@config.provider).name} · {@config.endpoint ||
                "s3.#{@config.region}.amazonaws.com"}</small>
            </div>
            <div :if={@config.kind != "bucket"}>
              <strong>On this server</strong>
              <small>{Storehouse.Local.config()[:root]}</small>
            </div>
          </div>

          <.form
            for={@form}
            id="storage-form"
            phx-change="validate"
            phx-submit="save"
            class="settings-form storage-form"
          >
            <fieldset class="storage-kinds">
              <legend>Keep new files</legend>
              <label class={["storage-kind", @kind == "local" && "is-chosen"]}>
                <input type="radio" name={@form[:kind].name} value="local" checked={@kind == "local"} />
                <.icon name="hero-server" class="size-5" />
                <span><strong>On this server</strong><small>Its disk, beside the database.</small></span>
              </label>
              <label class={["storage-kind", @kind == "bucket" && "is-chosen"]}>
                <input
                  type="radio"
                  name={@form[:kind].name}
                  value="bucket"
                  checked={@kind == "bucket"}
                />
                <.icon name="hero-cloud" class="size-5" />
                <span>
                  <strong>In a bucket</strong><small>Amazon S3, Cloudflare R2, Tigris, Backblaze B2, MinIO…</small>
                </span>
              </label>
            </fieldset>

            <div :if={@kind == "bucket"} class="storage-bucket">
              <.input
                field={@form[:provider]}
                type="select"
                label="Store"
                options={Enum.map(Storage.providers(), &{&1.name, &1.id})}
              />
              <.input
                :if={@provider.id != "aws"}
                field={@form[:endpoint]}
                type="url"
                label="Endpoint"
                placeholder={@provider.endpoint}
                autocomplete="off"
              />
              <div class="storage-pair">
                <.input field={@form[:bucket]} type="text" label="Bucket" autocomplete="off" />
                <.input
                  field={@form[:region]}
                  type="text"
                  label="Region"
                  placeholder={@provider.region}
                  autocomplete="off"
                />
              </div>
              <div class="storage-pair">
                <.input
                  field={@form[:access_key_id]}
                  type="text"
                  label="Access key ID"
                  autocomplete="off"
                />
                <.input
                  field={@form[:secret_access_key]}
                  type="password"
                  label="Secret access key"
                  value=""
                  placeholder={if @config.secret?, do: "Kept. Type a new one to change it", else: ""}
                  autocomplete="new-password"
                />
              </div>

              <fieldset class="storage-serve">
                <legend>Serve the files</legend>
                <label>
                  <input
                    type="radio"
                    name={@form[:serve].name}
                    value="app"
                    checked={@form[:serve].value != "redirect"}
                  />
                  <span>
                    <strong>Through the notebook</strong>
                    <small>The bucket stays private; each file goes by this server.</small>
                  </span>
                </label>
                <label>
                  <input
                    type="radio"
                    name={@form[:serve].name}
                    value="redirect"
                    checked={@form[:serve].value == "redirect"}
                  />
                  <span>
                    <strong>Straight from the bucket</strong>
                    <small>By links the bucket signs for five minutes: lighter for this server.</small>
                  </span>
                </label>
              </fieldset>

              <p class="storage-hint">
                <.icon name="hero-light-bulb" class="size-4" />
                <span>
                  A Google Drive, Dropbox or OneDrive speaks S3 through <a
                    href="https://rclone.org/commands/rclone_serve_s3/"
                    target="_blank"
                    rel="noopener"
                  >rclone serve s3</a>:
                  give its address as the endpoint.
                </span>
              </p>
            </div>

            <button
              class="button button-primary"
              type="submit"
              phx-disable-with="Checking the bucket…"
            >
              {if @kind == "bucket", do: "Check and save", else: "Save"}
            </button>
          </.form>

          <div :if={@other} class="storage-copy" id="storage-copy">
            <div>
              <strong>{copy_title(@other, @last_copy)}</strong>
              <p :if={is_nil(@last_copy)}>
                They are served from there until they are copied. A copy keeps their addresses,
                and skips what is there already, so it can run again.
              </p>
              <p :if={@last_copy && is_nil(@copying)} class="storage-copied">
                Last copy: {@last_copy["copied"]} copied, {@last_copy["skipped"]} there already<span :if={
                  @last_copy["failed"] > 0
                }>, {@last_copy["failed"]} failed</span>.
                Remove the originals to free their room: only those the store has, the same size, go.
              </p>
            </div>
            <div :if={is_nil(@copying) and not @removing} class="storage-copy-actions">
              <button type="button" class="button" phx-click="copy" id="storage-copy-start">
                {if @last_copy, do: "Copy again", else: copy_action(@other)}
              </button>
              <button
                :if={@last_copy}
                type="button"
                class="button button-primary"
                phx-click="prune"
                id="storage-prune"
                data-confirm={"Remove the files #{place(@other)} that the store has now?"}
              >
                Remove them from {where(@other)}
              </button>
            </div>
            <span :if={@copying} class="storage-copying">
              <.icon name="hero-arrow-path" class="size-4 animate-spin" /> Copying… {@copying} files
            </span>
            <span :if={@removing} class="storage-copying">
              <.icon name="hero-arrow-path" class="size-4 animate-spin" /> Removing…
            </span>
          </div>
        </section>
      </div>
    </main>
    """
  end

  defp copy_title(store, nil), do: "Files from before are still #{place(store)}"
  defp copy_title(store, _copied), do: "Copied. The originals are still #{place(store)}"

  defp place(Storehouse.Local), do: "on this server"
  defp place(_bucket), do: "in the bucket"

  defp where(Storehouse.Local), do: "this server"
  defp where(_bucket), do: "the bucket"

  defp copy_action(Storehouse.Local), do: "Copy them to the bucket"
  defp copy_action(_bucket), do: "Copy them to this server"
end
