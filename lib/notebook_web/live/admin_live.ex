defmodule NotebookWeb.AdminLive do
  @moduledoc """
  The notebook's own settings, for its admins: where its files are kept
  (`Notebook.Storage`), on this server or in a bucket, and the copy of
  the files from one to the other.
  """
  use NotebookWeb, :live_view

  alias Notebook.Accounts.Scope
  alias Notebook.Storage
  alias Notebook.Storage.Usage

  @impl true
  def mount(_params, _session, socket) do
    if Scope.admin?(socket.assigns.current_scope) do
      if connected?(socket), do: Storage.subscribe()
      config = Storage.config()

      {:ok,
       socket
       |> assign(page_title: "Notebook settings", config: config, samples: [])
       |> assign_form(Storage.change(config))
       |> assign_other()
       |> assign_usage()}
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
    assign(socket, other: other, transfer: Storage.transfer())
  end

  # The disk and the database at once; the files counted after, as there
  # may be many.
  defp assign_usage(socket) do
    stores = Enum.reject([Storehouse.Local, Storage.adapter(), socket.assigns.other], &is_nil/1)

    socket
    |> assign(disk: Usage.disk(Usage.root()), database: Usage.database(), files: %{})
    |> start_async(:files, fn -> Map.new(Enum.uniq(stores), &{&1, Usage.files(&1)}) end)
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
         |> assign_usage()
         |> put_flash(:info, saved(config))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "Only the notebook's admins change its settings.")}
    end
  end

  def handle_event("transfer", %{"action" => action}, socket) when action in ["copy", "remove"] do
    case Storage.start_transfer(socket.assigns.current_scope, action) do
      {:ok, transfer} -> {:noreply, assign(socket, transfer: transfer, samples: [])}
      {:error, :busy} -> {:noreply, put_flash(socket, :error, "Files are moving already.")}
      {:error, _reason} -> {:noreply, put_flash(socket, :error, "There are no files to move.")}
    end
  end

  def handle_event("stop", _params, socket) do
    case Storage.stop_transfer(socket.assigns.current_scope) do
      {:ok, transfer} -> {:noreply, assign(socket, transfer: transfer)}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  def handle_event("resume", _params, socket) do
    case Storage.resume_transfer(socket.assigns.current_scope) do
      {:ok, transfer} -> {:noreply, assign(socket, transfer: transfer, samples: [])}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  @impl true
  def handle_async(:files, {:ok, files}, socket), do: {:noreply, assign(socket, files: files)}
  def handle_async(:files, {:exit, _reason}, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:storage, :transfer, %{"state" => state} = transfer}, socket)
      when state in ["counting", "running"] do
    {:noreply,
     assign(socket, transfer: transfer, samples: sample(socket.assigns.samples, transfer))}
  end

  # Done or stopped: what is where now.
  def handle_info({:storage, :transfer, transfer}, socket) do
    {:noreply,
     socket
     |> assign_other()
     |> assign(transfer: transfer, samples: [])
     |> assign_usage()}
  end

  def handle_info({:storage, :saved}, socket) do
    config = Storage.config()
    {:noreply, socket |> assign(config: config) |> assign_other()}
  end

  # The bytes done, at most a minute back: how fast they go now.
  defp sample(samples, %{"done_bytes" => bytes}) do
    now = System.monotonic_time(:millisecond)
    Enum.take_while([{now, bytes} | samples], fn {at, _bytes} -> now - at < 60_000 end)
  end

  defp rate([{t1, b1} | _rest] = samples) when length(samples) > 1 do
    {t0, b0} = List.last(samples)
    if t1 > t0, do: (b1 - b0) * 1000 / (t1 - t0)
  end

  defp rate(_samples), do: nil

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
        <p><.link navigate={~p"/bots"} class="copy-action">The notebook's bots →</.link></p>
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

          <.usage config={@config} disk={@disk} database={@database} files={@files} />

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

          <.transfer other={@other} transfer={@transfer} files={@files} rate={rate(@samples)} />
        </section>
      </div>
    </main>
    """
  end

  attr :config, :any, required: true
  attr :disk, :map, default: nil
  attr :database, :integer, default: 0
  attr :files, :map, default: %{}

  # Where the files are now, and the room they take: this server's disk,
  # as a bar of the notebook's files, its database, the rest and what is
  # free; the bucket's files, counted.
  defp usage(assigns) do
    local = assigns.files[Storehouse.Local]
    disk = assigns.disk
    files = (local && local.bytes) || 0

    # The bar is of the room there is to use: what is used and what is free
    # (a disk keeps some for its system, and a container may see a bigger one).
    room = disk && disk.used + disk.free

    segments =
      if room && room > 0 do
        other = max(disk.used - files - assigns.database, 0)

        for {name, bytes} <- [files: files, database: assigns.database, other: other],
            do: {name, Float.round(bytes * 100 / room, 2)}
      end

    assigns =
      assign(assigns,
        local: local,
        bucket: assigns.files[Storehouse.S3],
        segments: segments,
        full: room && room > 0 && round(disk.used * 100 / room)
      )

    ~H"""
    <div class="storage-usage" id="storage-usage">
      <div class={["storage-now", @config.kind == "bucket" && "is-bucket"]}>
        <.icon
          name={if @config.kind == "bucket", do: "hero-cloud", else: "hero-server"}
          class="size-5"
        />
        <div :if={@config.kind == "bucket"}>
          <strong>New files go to the bucket {@config.bucket}</strong>
          <small>
            {provider(@config.provider).name} · {@config.endpoint ||
              "s3.#{@config.region}.amazonaws.com"}
          </small>
        </div>
        <div :if={@config.kind != "bucket"}>
          <strong>New files are kept on this server</strong>
          <small>{Usage.root()}</small>
        </div>
      </div>

      <div :if={@disk} class="storage-disk">
        <div class="storage-disk-head">
          <strong>This server's disk</strong>
          <span>
            <b>{Usage.human(@disk.free)}</b> free of {Usage.human(@disk.total)}
          </span>
        </div>
        <div
          class={["storage-bar", @full >= 85 && "is-full"]}
          role="img"
          aria-label={"#{@full}% of the disk is used"}
        >
          <span :for={{name, percent} <- @segments} class={"is-#{name}"} style={"width: #{percent}%"}></span>
        </div>
        <ul class="storage-legend">
          <li class="is-files">
            Files here <b>{if @local, do: Usage.human(@local.bytes), else: "counting…"}</b>
            <small :if={@local}>{count(@local.count)}</small>
          </li>
          <li class="is-database">Database <b>{Usage.human(@database)}</b></li>
          <li class="is-other">
            Everything else
            <b>{Usage.human(max(@disk.used - ((@local && @local.bytes) || 0) - @database, 0))}</b>
          </li>
          <li class="is-free">Free <b>{Usage.human(@disk.free)}</b></li>
        </ul>
        <p :if={@full >= 85 and @config.kind != "bucket"} class="storage-warning">
          <.icon name="hero-exclamation-triangle" class="size-4" />
          The disk is {@full}% full. A bucket keeps the files off it.
        </p>
      </div>

      <div :if={@config.kind == "bucket"} class="storage-bucket-usage">
        <.icon name="hero-cloud" class="size-4" />
        <span>
          In the bucket:
          <b>{if @bucket,
            do: "#{Usage.human(@bucket.bytes)} · #{count(@bucket.count)}",
            else: "counting…"}</b>
        </span>
      </div>
    </div>
    """
  end

  attr :other, :any, default: nil
  attr :transfer, :map, default: nil
  attr :files, :map, default: %{}
  attr :rate, :any, default: nil

  # The files of before, and their move to where new files go: a copy,
  # then the originals removed, with its progress as it goes.
  defp transfer(assigns) do
    transfer = assigns.transfer
    active? = transfer && transfer["state"] in ["counting", "running", "stopped"]

    assigns =
      assign(assigns,
        active?: active?,
        percent: percent(transfer),
        left: left(transfer, assigns.rate),
        from: transfer && store(transfer["from"]),
        held: assigns.other && assigns.files[assigns.other]
      )

    ~H"""
    <div :if={@other || @active?} class="storage-copy" id="storage-copy">
      <%= cond do %>
        <% @active? -> %>
          <div class="storage-progress">
            <div class="storage-progress-head">
              <strong>
                {verb(@transfer)} {if @transfer["action"] == "copy",
                  do: "to #{where_to(@from)}",
                  else: "from #{where(@from)}"}
              </strong>
              <span :if={@transfer["total"]}>{@percent}%</span>
            </div>
            <div class={[
              "storage-bar storage-progress-bar",
              @transfer["state"] == "counting" && "is-counting"
            ]}>
              <span class="is-files" style={"width: #{@percent}%"}></span>
            </div>
            <p :if={@transfer["state"] == "counting"}>
              Counting the files{if @transfer["total"],
                do: "… #{count(@transfer["total"])}",
                else: "…"}
            </p>
            <p :if={@transfer["total"]}>
              {number(@transfer["done"])} of {count(@transfer["total"])} · {Usage.human(
                @transfer["done_bytes"]
              )} of {Usage.human(@transfer["total_bytes"])}
              <span :if={@left && @transfer["state"] == "running"}> · {@left}</span>
            </p>
            <p :if={@transfer["failed"] > 0} class="storage-failed">
              {count(@transfer["failed"])} couldn't be moved yet; they are kept where they are.
            </p>
            <p :if={@transfer["state"] != "stopped"} class="storage-progress-note">
              It goes on in the background: leave this page, or restart the notebook, and it carries on.
            </p>
            <p :if={@transfer["state"] == "stopped"} class="storage-progress-note">
              Stopped. It goes on from where it was, and the files already moved stay where they are.
            </p>
          </div>
          <div class="storage-copy-actions">
            <button
              :if={@transfer["state"] != "stopped"}
              type="button"
              class="button"
              phx-click="stop"
              id="storage-stop"
            >
              Stop
            </button>
            <button
              :if={@transfer["state"] == "stopped"}
              type="button"
              class="button button-primary"
              phx-click="resume"
              id="storage-resume"
            >
              Go on
            </button>
          </div>
        <% @transfer && @transfer["action"] == "copy" && @transfer["state"] == "done" && @other -> %>
          <div>
            <strong>Copied. The originals are still {place(@other)}</strong>
            <p class="storage-copied">
              {count(@transfer["moved"])} copied, {number(@transfer["skipped"])} there already<span :if={
                @transfer["failed"] > 0
              }>, {number(@transfer["failed"])} failed</span>.
              Remove the originals to free their room: only those the new store has, the same size, go.
            </p>
            <.errors errors={@transfer["errors"]} />
          </div>
          <div class="storage-copy-actions">
            <button
              type="button"
              class="button"
              phx-click="transfer"
              phx-value-action="copy"
              id="storage-copy-start"
            >
              Copy again
            </button>
            <button
              type="button"
              class="button button-primary"
              phx-click="transfer"
              phx-value-action="remove"
              id="storage-prune"
              data-confirm={"Remove the files #{place(@other)} that the new store has now?"}
            >
              Remove them from {where(@other)}
            </button>
          </div>
        <% true -> %>
          <div>
            <strong>Files from before are still {place(@other)}</strong>
            <p>
              <span :if={@held}>{count(@held.count)}, {Usage.human(@held.bytes)}. </span>
              They are served from there until they are copied. A copy keeps their addresses,
              skips what is there already, and shows how far it is.
            </p>
          </div>
          <div class="storage-copy-actions">
            <button
              type="button"
              class="button button-primary"
              phx-click="transfer"
              phx-value-action="copy"
              id="storage-copy-start"
            >
              Copy them to {where_to(@other)}
            </button>
          </div>
      <% end %>
    </div>
    <p
      :if={
        @transfer && @transfer["action"] == "remove" && @transfer["state"] == "done" && is_nil(@other)
      }
      class="storage-moved"
      id="storage-moved"
    >
      <.icon name="hero-check-circle" class="size-5" />
      All the files are where new files go: {count(@transfer["moved"])} removed from {where(
        store(@transfer["from"])
      )}.
    </p>
    """
  end

  attr :errors, :list, default: []

  defp errors(assigns) do
    ~H"""
    <details :if={@errors != []} class="storage-errors">
      <summary>What failed</summary>
      <ul>
        <li :for={error <- @errors}><code>{error["key"]}</code> {error["reason"]}</li>
      </ul>
    </details>
    """
  end

  defp verb(%{"state" => "stopped", "action" => "copy"}), do: "Copying stopped, on the way"
  defp verb(%{"state" => "stopped"}), do: "Removing stopped, on the way"
  defp verb(%{"action" => "copy"}), do: "Copying the files"
  defp verb(_transfer), do: "Removing the files"

  defp percent(%{"total" => total, "done" => done}) when is_integer(total) and total > 0,
    do: min(floor(done * 100 / total), 100)

  defp percent(%{"total" => 0}), do: 100
  defp percent(_transfer), do: 0

  # The time left, at the rate of the last minute.
  defp left(%{"total_bytes" => total, "done_bytes" => done}, rate)
       when is_integer(total) and is_number(rate) and rate > 0 do
    seconds = round((total - done) / rate)

    cond do
      seconds < 60 -> "less than a minute left"
      seconds < 3600 -> "about #{div(seconds, 60) + 1} minutes left"
      true -> "about #{Float.round(seconds / 3600, 1)} hours left"
    end <> " · #{Usage.human(round(rate))}/s"
  end

  defp left(_transfer, _rate), do: nil

  defp count(1), do: "1 file"
  defp count(n), do: "#{number(n)} files"

  defp number(n) when is_integer(n),
    do:
      n
      |> Integer.to_string()
      |> String.reverse()
      |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
      |> String.reverse()

  defp number(_n), do: "0"

  defp store("Storehouse.Local"), do: Storehouse.Local
  defp store(_bucket), do: Storehouse.S3

  defp place(Storehouse.Local), do: "on this server"
  defp place(_bucket), do: "in the bucket"

  defp where(Storehouse.Local), do: "this server"
  defp where(_bucket), do: "the bucket"

  # Where the files of `from` go: the other place.
  defp where_to(Storehouse.Local), do: "the bucket"
  defp where_to(_bucket), do: "this server"
end
