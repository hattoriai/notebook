defmodule Notebook.Databases do
  @moduledoc """
  Database pages: records of one kind with fields people define, seen as
  a table (Masu), a board (Narabe), a calendar (Koyomi) or a chart (Fude).
  A database page owns a Cardbox collection (`Notebook.Cardbox`); who may
  read and change it is who may read and edit the page.

  A new database starts with a Name, a Status, an Owner, a Due date and
  Tags, and a view of each type.
  """
  alias Notebook.Accounts.{Scope, User}
  alias Notebook.Cardbox, as: Box
  alias Notebook.Pages.Page
  alias Notebook.{Pages, Spaces}

  @default_fields [
    %{name: "Name", type: "text"},
    %{name: "Status", type: "status"},
    %{name: "Owner", type: "person"},
    %{name: "Due", type: "date"},
    %{name: "Tags", type: "multi_select", options: %{choices: []}}
  ]

  @view_types [
    {"table", "Table", "hero-table-cells"},
    {"board", "Board", "hero-view-columns"},
    {"calendar", "Calendar", "hero-calendar-days"},
    {"chart", "Chart", "hero-chart-bar"}
  ]

  @field_types [
    {"text", "Text"},
    {"number", "Number"},
    {"checkbox", "Checkbox"},
    {"date", "Date"},
    {"select", "Select"},
    {"multi_select", "Multi-select"},
    {"status", "Status"},
    {"person", "Person"},
    {"url", "Link"},
    {"email", "Email"},
    {"file", "Files"},
    {"repeat", "Repeats"}
  ]

  @number_formats [
    {"number", "Number"},
    {"integer", "Whole number"},
    {"percent", "Percent"},
    {"currency", "Money"}
  ]

  # The largest file a record takes, from a person or an agent.
  @max_file 25_000_000

  @doc "The types of views a database shows: `{type, name, icon}`."
  def view_types, do: @view_types

  @doc "The types of fields people add: `{type, name}`."
  def field_types, do: @field_types

  @doc "How a number field shows its numbers: `{format, name}`."
  def number_formats, do: @number_formats

  @doc "The largest file a record takes."
  def max_file, do: @max_file

  @doc """
  Makes a database page's collection, with the default fields (or
  `fields`) and a view of each type: the scope edits the page.
  """
  def create(%Scope{} = scope, %Page{kind: "database"} = page, fields \\ @default_fields) do
    with {:ok, collection} <-
           Box.create_collection(%{name: page.title, owner: {"page", page.id}, fields: fields},
             actor: scope
           ) do
      for {type, name, _icon} <- @view_types,
          options = default_options(type, collection),
          options != :none do
        {:ok, _} =
          Box.save_view(collection, %{name: name, type: type, options: options}, actor: scope)
      end

      {:ok, Box.get_collection!(collection.id)}
    end
  end

  # A view's options from the collection's fields: a board groups by its
  # first status (or select, person, checkbox) and shows a few fields on
  # its cards, a calendar shows its first
  # date, a chart counts by what a board groups by. :none when it cannot.
  defp default_options("table", _collection), do: %{}

  defp default_options("board", collection) do
    case field_of(collection, ~w(status select person checkbox)) do
      nil -> :none
      field -> %{group_by: field.key, card_fields: card_fields(collection, field)}
    end
  end

  defp default_options("calendar", collection) do
    case field_of(collection, ~w(date)) do
      nil -> :none
      field -> %{date_field: field.key}
    end
  end

  defp default_options("chart", collection) do
    case field_of(collection, ~w(status select person checkbox)) do
      nil -> :none
      field -> %{kind: "bar", x: field.key, y: "count"}
    end
  end

  # Under a card's title: up to three of its people, days and choices,
  # not the one the board groups by.
  defp card_fields(collection, group_by) do
    collection.fields
    |> Enum.filter(&(&1.type in ~w(person date select multi_select) and &1.key != group_by.key))
    |> Enum.take(3)
    |> Enum.map(& &1.key)
  end

  defp field_of(collection, types), do: Enum.find(collection.fields, &(&1.type in types))

  @doc "A database page's collection, or nil."
  def collection(%Page{kind: "database", id: id}),
    do: List.first(Box.list_collections({"page", id}))

  def collection(_page), do: nil

  @doc "The collection's views, in their order."
  def views(collection), do: Box.list_views(collection)

  @doc "The people a person field offers: the members of the page's space, by `user:<id>`."
  def people(%Page{space_id: space_id}) do
    space_id
    |> then(&%Notebook.Spaces.Space{id: &1})
    |> Spaces.members()
    |> Enum.map(&%{id: "user:#{&1.user.id}", name: &1.user.name})
  end

  @doc "Who \"me\" is in a query: the scope's person."
  def me(%Scope{user: %User{id: id}}), do: "user:#{id}"

  @doc "The records of a view, for the scope."
  def records(scope, collection, view) do
    {:ok, records} = Box.list(collection, view, me: me(scope))
    records
  end

  @doc "Adds a view of a type: the page's editors may."
  def add_view(scope, collection, type) do
    case List.keyfind(@view_types, type, 0) do
      {^type, name, _icon} ->
        case default_options(type, collection) do
          :none ->
            {:error, "A #{String.downcase(name)} needs a field it can use: add one first."}

          options ->
            Box.save_view(collection, %{name: name, type: type, options: options}, actor: scope)
        end

      nil ->
        {:error, "No such view."}
    end
  end

  @doc """
  Adds a field: the page's editors may. A number takes its `format`, and
  a `currency` (`"EUR"`) as money; a repeat its `date` and `done` fields
  (by key), else the database's first date and its first status or
  checkbox.
  """
  def add_field(scope, collection, %{"name" => name, "type" => type} = params) do
    Box.add_field(
      collection,
      %{name: name, type: type, options: options(collection, type, params)},
      actor: scope
    )
  end

  defp options(_collection, type, _params) when type in ~w(select multi_select),
    do: %{choices: []}

  defp options(_collection, "number", params) do
    case params["format"] do
      "currency" -> %{format: "currency", currency: currency(params["currency"])}
      format when format in ~w(number integer percent) -> %{format: format}
      _ -> %{}
    end
  end

  defp options(collection, "repeat", params) do
    %{
      date: present(params["date"]) || key_of(field_of(collection, ~w(date))),
      done: present(params["done"]) || key_of(field_of(collection, ~w(status checkbox)))
    }
  end

  defp options(_collection, _type, _params), do: %{}

  defp currency(code) when is_binary(code), do: code |> String.trim() |> String.upcase()
  defp currency(_code), do: "EUR"

  defp present(value) when value in [nil, ""], do: nil
  defp present(value), do: value

  defp key_of(nil), do: nil
  defp key_of(field), do: field.key

  @doc "The fields of the database of a type: `{key, name}`, for a form's choices."
  def fields_of(collection, types),
    do: for(field <- collection.fields, field.type in types, do: {field.key, field.name})

  @doc """
  Stores a file for a database's records, as an upload of a page's is
  stored (Storehouse, `Kotoba.Attachments.store/2`: its bytes say what it
  is). Gives what a file field keeps of it.
  """
  def store_file(path, name, content_type \\ nil) do
    case File.stat(path) do
      {:ok, %{size: size}} when size > @max_file ->
        {:error, "#{name} is larger than #{div(@max_file, 1_000_000)} MB."}

      {:ok, _stat} ->
        opts = [
          name: name,
          content_type: content_type || Kotoba.Attachments.content_type(Path.extname(name))
        ]

        case Kotoba.Attachments.store(path, opts) do
          {:ok, node} -> {:ok, file(node)}
          {:error, reason} -> {:error, "#{name} could not be stored (#{inspect(reason)})."}
        end

      {:error, reason} ->
        {:error, "#{name} could not be read (#{inspect(reason)})."}
    end
  end

  defp file(%Kotoba.Nodes.Attachment{} = node) do
    %{
      key: node.key,
      url: node.url,
      name: node.name,
      content_type: node.content_type,
      bytes: node.bytes
    }
    |> then(&if(node.preview, do: Map.put(&1, :preview, node.preview), else: &1))
  end

  @doc "Removes stored files that no record took (after a write that failed)."
  def discard_files(files),
    do: for(%{key: key} <- files, do: Kotoba.Storage.adapter().delete(key))

  @doc """
  Adds files to a record's file field, after those it has: the page's
  editors may. `files` are what `store_file/3` gave.
  """
  def attach(scope, collection, record_id, field_ref, files) do
    with %Cardbox.Field{type: "file"} = field <- Cardbox.Collection.field(collection, field_ref),
         %Cardbox.Record{} = record <- Box.get(collection, record_id) do
      had = Map.get(record.data, field.key) || []

      case Box.update(collection, record.id, %{field.key => had ++ files}, actor: scope) do
        {:ok, record} ->
          {:ok, record}

        {:error, error} ->
          discard_files(files)
          {:error, error}
      end
    else
      _ ->
        discard_files(files)
        {:error, "No such record or file field."}
    end
  end

  @doc "Whether the scope may change the database: its page's editors."
  def editable?(scope, %Page{} = page), do: Pages.allowed?(scope, :edit, page)
end
