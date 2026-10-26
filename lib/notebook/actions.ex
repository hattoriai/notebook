defmodule Notebook.Actions do
  @moduledoc """
  What people and agents do in the Notebook by the same way
  (`Issho.Action`): a person from the page (its command palette, a
  database's Record button), an agent as a tool. Each runs in the page's
  room, under its policy (`Notebook.Collaboration`: who edits the page,
  and not on a page off limits to agents), as whoever runs it, and the
  room hears it done (`"action.done"`). A paused agent changes nothing.

    * `Notebook.Actions.RenamePage`: a page's title;
    * `Notebook.Actions.SetDueDate`: a page's due date;
    * `Notebook.Actions.AddRecords`: records of a database page.
  """

  alias Notebook.Pages

  @doc "Every action of the Notebook: the tools they are for an agent."
  def all, do: [__MODULE__.RenamePage, __MODULE__.SetDueDate, __MODULE__.AddRecords]

  @doc "The room of the page of that id: the action's target."
  def room(page_id), do: "page:#{page_id}"

  @doc """
  The page and the scope of whoever runs the invocation (`by`), for its
  change. The room's policy has said they edit it.
  """
  def page(page_id, %Issho.Action.Invocation{by: by}) do
    with {:ok, scope} <- Notebook.Collaboration.scope_of(by),
         %Pages.Page{} = page <- Pages.fetch(page_id) do
      {:ok, scope, page}
    else
      _ -> {:error, "No such page."}
    end
  end

  @doc "What went wrong in a page's change, in words a person or a model reads."
  def error(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join(". ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
  end

  def error(%Cardbox.Error{reason: :unauthorized}), do: "You may not change this database."
  def error(%Cardbox.Error{message: message}), do: message
  def error(_other), do: "You may not change this page."
end

defmodule Notebook.Actions.RenamePage do
  @moduledoc false
  use Issho.Action,
    name: "rename_page",
    description: """
    Renames a page, as the person you work for (they edit it). Gives its
    new title.
    """

  arg(:page_id, :integer, required: true, description: "The page, as list_pages gives it")
  arg(:title, :string, required: true, min_length: 1, max_length: 160)

  alias Notebook.Actions

  @impl Issho.Action
  def target(%{page_id: id}), do: Actions.room(id)

  @impl Issho.Action
  def run(%{page_id: id, title: title}, invocation) do
    with {:ok, scope, page} <- Actions.page(id, invocation) do
      case Notebook.Pages.update(scope, page, %{"title" => title}) do
        {:ok, page} -> {:ok, page}
        {:error, reason} -> {:error, Actions.error(reason)}
      end
    end
  end

  @impl Issho.Action
  def summary(page), do: "Renamed: #{page.title}."

  @impl Issho.Action
  def event(%{page_id: id}, page), do: %{page: id, title: page.title}
end

defmodule Notebook.Actions.SetDueDate do
  @moduledoc false
  use Issho.Action,
    name: "set_due_date",
    description: """
    Gives a page a due date, or takes it away, as the person you work for
    (they edit it). The page shows it, the calendar lists it, and its
    people are reminded.
    """

  arg(:page_id, :integer, required: true, description: "The page, as list_pages gives it")

  arg(:due, :string,
    required: true,
    max_length: 10,
    description: ~s(A day, "2026-11-02"; or "none" to take the due date away)
  )

  alias Notebook.Actions

  @impl Issho.Action
  def target(%{page_id: id}), do: Actions.room(id)

  @impl Issho.Action
  def run(%{page_id: id, due: due}, invocation) do
    with {:ok, scope, page} <- Actions.page(id, invocation),
         {:ok, day} <- day(due) do
      case Notebook.Pages.update(scope, page, %{"due_on" => day}) do
        {:ok, page} -> {:ok, page}
        {:error, reason} -> {:error, Actions.error(reason)}
      end
    end
  end

  defp day("none"), do: {:ok, nil}

  defp day(text) do
    case Date.from_iso8601(text) do
      {:ok, day} -> {:ok, day}
      {:error, _} -> {:error, ~s(Give the day as 2026-11-02, or "none".)}
    end
  end

  @impl Issho.Action
  def summary(%{due_on: nil, title: title}), do: "#{title} has no due date now."
  def summary(%{due_on: day, title: title}), do: "#{title} is due on #{Date.to_iso8601(day)}."

  @impl Issho.Action
  def event(%{page_id: id}, page),
    do: %{page: id, due: page.due_on && Date.to_iso8601(page.due_on)}
end

defmodule Notebook.Actions.AddRecords do
  @moduledoc false
  use Issho.Action,
    name: "add_records",
    description: """
    Adds records to a database page, as the person you work for (they edit
    the page): each one an object of values by field name or key, as
    read_database describes them. All of them are added, or none. Gives
    the records, with their ids.
    """

  arg(:page_id, :integer,
    required: true,
    description: "The database page, as list_pages gives it"
  )

  arg(:records, {:array, :any},
    required: true,
    description: ~s(The records' values, e.g. [{"Blade": "A short sword", "Status": "Asked"}])
  )

  alias Notebook.Actions
  alias Notebook.Cardbox, as: Box

  @impl Issho.Action
  def target(%{page_id: id}), do: Actions.room(id)

  @impl Issho.Action
  def run(%{page_id: id, records: records}, invocation) do
    with {:ok, scope, page} <- Actions.page(id, invocation),
         %Cardbox.Collection{} = collection <- Notebook.Databases.collection(page) do
      case Box.insert_all(collection, records, actor: scope) do
        {:ok, inserted} -> {:ok, {collection, inserted}}
        {:error, error} -> {:error, Actions.error(error)}
      end
    else
      nil -> {:error, "That page is not a database."}
      error -> error
    end
  end

  @impl Issho.Action
  def summary({collection, records}),
    do: %{"records" => Enum.map(records, &Notebook.Tools.Databases.record(collection, &1))}

  @impl Issho.Action
  def event(%{page_id: id}, {_collection, records}), do: %{page: id, count: length(records)}
end
