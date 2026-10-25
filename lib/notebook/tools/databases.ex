defmodule Notebook.Tools.Databases do
  @moduledoc """
  An agent's tools for database pages (Cardbox): it reads a database's
  fields, views and records, and adds and changes records, as the person
  it works for. Who may read a database and who may change it is who may
  read and edit its page.
  """
  alias Notebook.{Databases, Pages}

  @doc "The scope, the page and its collection of a database page the agent's person reads."
  def open(ctx, page_id) do
    with {:scope, %{} = scope} <- {:scope, Notebook.Tools.scope(ctx)},
         {:page, %{kind: "database"} = page} <- {:page, Pages.get(scope, page_id)},
         {:collection, %{} = collection} <- {:collection, Databases.collection(page)} do
      {:ok, scope, page, collection}
    else
      {:scope, nil} ->
        {:error,
         "Databases are read for a person: connect as one (see the Notebook's Agents page)."}

      {_missing, _} ->
        {:error,
         "No database page of that id that the person you work for may read: list_pages gives them."}
    end
  end

  @doc "A record as an agent reads it: its values by field name, and its id."
  def record(collection, record), do: Cardbox.Record.to_map(record, collection)

  @doc "What went wrong in a write, in words a model reads."
  def error(%Cardbox.Error{reason: :unauthorized}),
    do: {:error, "The person you work for may not change this database: they read its page only."}

  def error(%Cardbox.Error{message: message}), do: {:error, message}
  def error(other), do: {:error, inspect(other)}

  @doc "Whether the scope may change the page's database."
  def editable?(scope, page), do: Databases.editable?(scope, page)

  @doc "The records of a write, after it: by id."
  def written(collection, records),
    do: {:ok, %{"records" => Enum.map(records, &record(collection, &1))}}
end

defmodule Notebook.Tools.ReadDatabase do
  @moduledoc false
  use Issho.Tool,
    name: "read_database",
    description: """
    A database page's fields (each one's key, name, type, choices and the
    operators it filters by), its views, the people a person field takes,
    and its records: those of a view when you name one, or all of them,
    filtered when you give a filter. A record's values are by field name;
    a person is their id (`user:7`), a choice its name, a day
    `2026-10-25`. Read it before add_records and update_records.
    """,
    annotations: [read_only: true, idempotent: true]

  arg(:page_id, :integer,
    required: true,
    description: "The database page, as list_pages gives it"
  )

  arg(:view, :string, description: "The name of one of its views: its records, in its order")

  arg(:filter, :any,
    description: """
    A filter of the records, as Cardbox takes one: {"field": "Status",
    "op": "eq", "value": "Forging"}, or {"and": [...]} / {"or": [...]}.
    "me" is the person you work for.
    """
  )

  arg(:limit, :integer,
    min: 1,
    max: 500,
    description: "At most this many records (100 unless given)"
  )

  alias Notebook.Cardbox, as: Box
  alias Notebook.Databases
  alias Notebook.Tools.Databases, as: T

  @impl true
  def call(args, ctx) do
    with {:ok, scope, page, collection} <- T.open(ctx, args.page_id),
         {:ok, query} <- query(collection, args[:view], args[:filter]),
         {:ok, records} <-
           Box.list(collection, query, me: Databases.me(scope), limit: args[:limit] || 100) do
      {:ok,
       Cardbox.describe(collection)
       |> Map.merge(%{
         "page" => page.id,
         "editable" => T.editable?(scope, page),
         "views" =>
           for(
             view <- Databases.views(collection),
             do: %{"name" => view.name, "type" => view.type}
           ),
         "people" => Databases.people(page),
         "records" => Enum.map(records, &T.record(collection, &1))
       })}
    else
      {:error, %Cardbox.Error{} = error} -> T.error(error)
      {:error, message} -> {:error, message}
    end
  end

  # The view's query, the filter given within it.
  defp query(collection, view_name, filter) do
    view = view_name && Enum.find(Databases.views(collection), &(&1.name == view_name))

    cond do
      view_name && is_nil(view) ->
        {:error, "No view of that name: read_database without one lists them."}

      is_nil(filter) ->
        {:ok, view}

      true ->
        wire = (view && view.query) || %{}
        filters = Enum.reject([wire["filter"], filter], &is_nil/1)
        {:ok, Map.put(wire, "filter", %{"and" => filters})}
    end
  end
end

defmodule Notebook.Tools.AddRecords do
  @moduledoc false
  use Issho.Tool,
    name: "add_records",
    description: """
    Adds records to a database page, as the person you work for (they edit
    the page): each one an object of values by field name or key, as
    read_database describes them. All of them are added, or none. Gives
    the records, with their ids.
    """,
    annotations: []

  arg(:page_id, :integer,
    required: true,
    description: "The database page, as list_pages gives it"
  )

  arg(:records, {:array, :any},
    required: true,
    description: ~s(The records' values, e.g. [{"Blade": "A short sword", "Status": "Asked"}])
  )

  alias Notebook.Cardbox, as: Box
  alias Notebook.Tools.Databases, as: T

  @impl true
  def call(%{page_id: page_id, records: records}, ctx) do
    with {:ok, scope, _page, collection} <- T.open(ctx, page_id) do
      case Box.insert_all(collection, records, actor: scope) do
        {:ok, records} -> T.written(collection, records)
        {:error, error} -> T.error(error)
      end
    end
  end
end

defmodule Notebook.Tools.UpdateRecords do
  @moduledoc false
  use Issho.Tool,
    name: "update_records",
    description: """
    Changes records of a database page, as the person you work for (they
    edit the page): each change names a record's id and the values to
    give it, by field name or key; null empties a value. Gives the records
    as they are after it.
    """,
    annotations: [idempotent: true]

  arg(:page_id, :integer,
    required: true,
    description: "The database page, as list_pages gives it"
  )

  arg(
    :changes,
    {:array,
     {:object,
      [
        {:id, :integer, required: true, description: "The record's id"},
        {:values, :any, required: true, description: ~s(e.g. {"Status": "Delivered"})}
      ]}},
    required: true
  )

  alias Notebook.Cardbox, as: Box
  alias Notebook.Tools.Databases, as: T

  @impl true
  def call(%{page_id: page_id, changes: changes}, ctx) do
    with {:ok, scope, _page, collection} <- T.open(ctx, page_id) do
      changes
      |> Enum.reduce_while({:ok, []}, fn %{id: id, values: values}, {:ok, done} ->
        case Box.update(collection, id, values, actor: scope) do
          {:ok, record} -> {:cont, {:ok, [record | done]}}
          {:error, error} -> {:halt, T.error(error)}
        end
      end)
      |> case do
        {:ok, records} -> T.written(collection, Enum.reverse(records))
        error -> error
      end
    end
  end
end
