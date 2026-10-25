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
    {"email", "Email"}
  ]

  @doc "The types of views a database shows: `{type, name, icon}`."
  def view_types, do: @view_types

  @doc "The types of fields people add: `{type, name}`."
  def field_types, do: @field_types

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

  @doc "Adds a field: the page's editors may."
  def add_field(scope, collection, %{"name" => name, "type" => type}) do
    options = if type in ~w(select multi_select), do: %{choices: []}, else: %{}
    Box.add_field(collection, %{name: name, type: type, options: options}, actor: scope)
  end

  @doc "Whether the scope may change the database: its page's editors."
  def editable?(scope, %Page{} = page), do: Pages.allowed?(scope, :edit, page)
end
