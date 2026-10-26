defmodule NotebookWeb.BotsLive do
  @moduledoc """
  The notebook's bots, for its admins (`Notebook.Bots`): the Claude API's
  key they think with, and each bot: what it is told, its model and its
  tools, what wakes it, its schedule, what it may spend a month, its role
  in each space, and its last runs. The notebook comes with no bot: its
  admins make the ones they want.
  """
  use NotebookWeb, :live_view

  alias Notebook.Accounts.Scope
  alias Notebook.Bots
  alias Notebook.Bots.Bot

  @impl true
  def mount(_params, _session, socket) do
    if Scope.admin?(socket.assigns.current_scope) do
      {:ok,
       socket
       |> assign(page_title: "Bots", api_key?: Bots.api_key?(), editing: nil, form: nil)
       |> assign_bots()}
    else
      {:ok,
       socket
       |> put_flash(:error, "Only the notebook's admins make its bots.")
       |> push_navigate(to: ~p"/")}
    end
  end

  defp assign_bots(socket), do: assign(socket, bots: Bots.list(socket.assigns.current_scope))

  defp edit(socket, %Bot{} = bot, changeset) do
    assign(socket,
      editing: bot,
      form: to_form(changeset, as: :bot),
      spaces: if(bot.id, do: Bots.spaces(bot), else: []),
      runs: if(bot.id, do: Bots.runs(bot), else: [])
    )
  end

  @impl true
  def handle_event("new", _params, socket),
    do: {:noreply, edit(socket, %Bot{}, Bots.change(%Bot{}))}

  def handle_event("edit", %{"id" => id}, socket) do
    bot = Bots.get!(socket.assigns.current_scope, id)
    {:noreply, edit(socket, bot, Bots.change(bot))}
  end

  def handle_event("close", _params, socket),
    do: {:noreply, assign(socket, editing: nil, form: nil)}

  def handle_event("validate", %{"bot" => params}, socket) do
    bot = socket.assigns.editing
    changeset = bot |> Bots.change(attrs(params)) |> Map.put(:action, :validate)
    {:noreply, assign(socket, form: to_form(changeset, as: :bot))}
  end

  def handle_event("save", %{"bot" => params}, socket) do
    scope = socket.assigns.current_scope
    bot = socket.assigns.editing

    result =
      if bot.id,
        do: Bots.update(scope, bot, attrs(params)),
        else: Bots.create(scope, attrs(params))

    case result do
      {:ok, saved} ->
        message =
          if bot.id,
            do: "#{saved.name} is saved.",
            else: "#{saved.name} is made. Give it a role in the spaces it works in."

        {:noreply,
         socket |> assign_bots() |> edit(saved, Bots.change(saved)) |> put_flash(:info, message)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :bot))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "The bot could not be saved.")}
    end
  end

  def handle_event("delete", _params, socket) do
    bot = socket.assigns.editing
    {:ok, _} = Bots.delete(socket.assigns.current_scope, bot)

    {:noreply,
     socket
     |> assign(editing: nil, form: nil)
     |> assign_bots()
     |> put_flash(:info, "#{bot.name} is deleted, with its runs.")}
  end

  def handle_event("role", %{"space" => space_id, "role" => role}, socket) do
    bot = socket.assigns.editing

    {space, _role} =
      Enum.find(socket.assigns.spaces, fn {space, _} -> to_string(space.id) == space_id end)

    role = if role == "", do: nil, else: role

    case Bots.set_role(socket.assigns.current_scope, bot, space, role) do
      {:ok, _} -> {:noreply, assign(socket, spaces: Bots.spaces(bot))}
      {:error, _} -> {:noreply, put_flash(socket, :error, "That role could not be given.")}
    end
  end

  def handle_event("api_key", %{"key" => key}, socket) do
    :ok = Bots.put_api_key(socket.assigns.current_scope, key)

    {:noreply,
     socket
     |> assign(api_key?: Bots.api_key?())
     |> put_flash(
       :info,
       if(String.trim(key) == "", do: "The key is removed.", else: "The key is kept.")
     )}
  end

  # The form's values as a bot takes them: its groups of tools without the
  # empty one the form sends, its budget in cents from dollars.
  defp attrs(params) do
    params
    |> Map.update("tools", [], fn tools -> Enum.reject(List.wrap(tools), &(&1 == "")) end)
    |> then(fn params ->
      case Float.parse(to_string(params["budget"] || "")) do
        {dollars, _} -> Map.put(params, "monthly_budget_cents", round(dollars * 100))
        :error -> params
      end
    end)
  end

  defp dollars(micros), do: :erlang.float_to_binary(micros / 1_000_000, decimals: 2)
  defp budget(cents), do: :erlang.float_to_binary((cents || 0) / 100, decimals: 2)

  defp wakes(%Bot{} = bot) do
    [
      bot.on_mention && "mentions and tasks",
      bot.public && "visitors",
      bot.on_new_page && "new pages",
      bot.schedule && Bots.describe_schedule(bot)
    ]
    |> Enum.filter(& &1)
    |> case do
      [] -> "nothing yet"
      list -> Enum.join(list, ", ")
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="settings-page bots-page">
      <div class="page-nav">
        <.link navigate={~p"/admin"}>← Notebook settings</.link><span>BOTS</span>
      </div>
      <div class="page-heading">
        <p class="eyebrow">This notebook</p>
        <h1>Bots</h1>
        <p>
          The notebook's own bots: each works in the pages as itself, with what you tell it, the
          tools you give it and the spaces you add it to, when it is mentioned, handed a task,
          asked by a visitor, given a new page or its schedule comes. Everyone on a page sees it
          there, and can pause or stop it. The notebook comes with none: make the ones you want.
        </p>
      </div>
      <Layouts.flash_group flash={@flash} />

      <section class="settings-wide" id="bots-api">
        <h2>The Claude API</h2>
        <p :if={@api_key?}>
          A key is kept, encrypted with the notebook's secrets. Bots think with it; what they spend
          is billed to it.
        </p>
        <p :if={!@api_key?}>
          Bots think with Claude: give the notebook a key of the Claude API (console.anthropic.com),
          kept encrypted with its secrets. Without one, no bot runs.
        </p>
        <form id="api-key-form" phx-submit="api_key" class="settings-form bots-key">
          <input
            type="password"
            name="key"
            placeholder={if @api_key?, do: "A new key, or empty to remove it", else: "sk-ant-…"}
            autocomplete="off"
            aria-label="The Claude API's key"
          />
          <button class="button" type="submit">{if @api_key?, do: "Change", else: "Keep it"}</button>
        </form>
      </section>

      <section class="settings-wide" id="bots-list">
        <div class="bots-head">
          <h2>The bots</h2>
          <button type="button" class="button button-primary" phx-click="new">
            <.icon name="hero-plus" class="size-4" /> New bot
          </button>
        </div>
        <p :if={@bots == []} class="field-hint">No bot yet.</p>
        <ul class="bots-list">
          <li :for={bot <- @bots} id={"bot-#{bot.id}"} class={["bot-card", !bot.enabled && "is-off"]}>
            <div>
              <strong>{bot.name}</strong>
              <span :if={!bot.enabled} class="bot-off">Off</span>
              <small>{bot.model} · wakes on {wakes(bot)}</small>
              <small>
                ${dollars(Bots.spent_micros(bot))} of ${budget(bot.monthly_budget_cents)} this month
              </small>
            </div>
            <button type="button" class="copy-action" phx-click="edit" phx-value-id={bot.id}>Edit</button>
          </li>
        </ul>
      </section>

      <section :if={@form} class="settings-wide bot-editor" id="bot-editor">
        <div class="bots-head">
          <h2>{if @editing.id, do: @editing.name, else: "A new bot"}</h2>
          <button type="button" class="copy-action" phx-click="close">Close</button>
        </div>
        <.form for={@form} id="bot-form" phx-change="validate" phx-submit="save" class="settings-form">
          <.input
            field={@form[:name]}
            type="text"
            label="Name"
            placeholder="Gardener, Docs, Librarian…"
          />
          <.input
            field={@form[:instructions]}
            type="textarea"
            label="What it is told"
            placeholder="Who it is, what it does, how it writes. Tidy the tags of new pages; answer visitors' questions from the docs…"
          />
          <div class="storage-pair">
            <.input field={@form[:model]} type="select" label="Model" options={Bot.models()} />
            <.input
              field={@form[:effort]}
              type="select"
              label="How hard it thinks"
              options={Bot.efforts()}
            />
          </div>

          <fieldset class="bot-tools">
            <legend>Its tools</legend>
            <input type="hidden" name="bot[tools][]" value="" />
            <label :for={{group, label, description, _tools} <- Bots.tool_groups()} class="bot-tool">
              <input
                type="checkbox"
                name="bot[tools][]"
                value={group}
                checked={group == "read" or group in (@form[:tools].value || [])}
                disabled={group == "read"}
              />
              <span><strong>{label}</strong><small>{description}</small></span>
            </label>
          </fieldset>

          <fieldset class="bot-wakes">
            <legend>What wakes it</legend>
            <.input
              field={@form[:on_mention]}
              type="checkbox"
              label="A mention, a task handed to it, a private question"
            />
            <.input
              field={@form[:public]}
              type="checkbox"
              label="A visitor's question on a published page it reads"
            />
            <.input
              field={@form[:on_new_page]}
              type="checkbox"
              label="A new page in a space it reads"
            />
            <.input
              field={@form[:schedule]}
              type="text"
              label="A schedule (a rule and a time)"
              placeholder="FREQ=WEEKLY;BYDAY=MO@09:00"
            />
            <.input
              :if={@form[:schedule].value not in [nil, ""]}
              field={@form[:schedule_task]}
              type="textarea"
              label="What to do then"
            />
          </fieldset>

          <div class="storage-pair">
            <.input
              name="bot[budget]"
              value={budget(@form[:monthly_budget_cents].value)}
              type="number"
              step="0.01"
              min="0"
              label="Most it spends a month ($)"
            />
            <.input field={@form[:enabled]} type="checkbox" label="On" />
          </div>
          <p :for={{message, _} <- @form[:monthly_budget_cents].errors} class="field-error">
            {message}
          </p>

          <div class="bot-actions">
            <button class="button button-primary" type="submit">Save</button>
            <button
              :if={@editing.id}
              type="button"
              class="copy-action danger"
              phx-click="delete"
              data-confirm={"Delete #{@editing.name}, its roles and its runs?"}
            >
              Delete
            </button>
          </div>
        </.form>

        <div :if={@editing.id} class="bot-spaces" id="bot-spaces">
          <h3>Its spaces</h3>
          <p class="field-hint">
            What it may do in each: read, comment, or edit. Never what is off limits to agents.
          </p>
          <form
            :for={{space, role} <- @spaces}
            id={"bot-space-#{space.id}"}
            phx-change="role"
            class="bot-space"
          >
            <input type="hidden" name="space" value={space.id} />
            <span>{space.name}</span>
            <select name="role" aria-label={"Its role in #{space.name}"}>
              <option value="" selected={is_nil(role)}>Not in it</option>
              <option :for={r <- ~w(viewer commenter editor)} value={r} selected={role == r}>
                {r}
              </option>
            </select>
          </form>
        </div>

        <div :if={@editing.id} class="bot-runs" id="bot-runs">
          <h3>Its last runs</h3>
          <p :if={@runs == []} class="field-hint">None yet.</p>
          <table :if={@runs != []}>
            <thead>
              <tr>
                <th>When</th><th>Woken by</th><th>How it ended</th><th>Steps</th><th>Cost</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={run <- @runs} id={"run-#{run.id}"}>
                <td>{Calendar.strftime(run.inserted_at, "%-d %b %H:%M")}</td>
                <td>{run.trigger}</td>
                <td title={run.error || run.summary}>{run.status}{run.error && ": " <> run.error}</td>
                <td>{run.steps}</td>
                <td>${dollars(run.cost_micros)}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </main>
    """
  end
end
