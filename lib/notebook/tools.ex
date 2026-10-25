defmodule Notebook.Tools do
  @moduledoc """
  What an agent can do in the Notebook, however it connects: the tools
  of the pages' rooms (Issho's), of their parts (Kotoba's text, Hakushi's
  board, Masu's table, Fude's charts), and the Notebook's own: to find the
  pages, to make one, and to read and write a database's records
  (`Notebook.Tools.Databases`).
  """

  @doc "Every tool of the Notebook, for MCP (NotebookWeb.MCP) or an app's own model."
  def all do
    [Notebook.Tools.ListPages, Notebook.Tools.CreatePage] ++
      [Notebook.Tools.ReadDatabase, Notebook.Tools.AddRecords, Notebook.Tools.UpdateRecords] ++
      Issho.Tools.room() ++
      Kotoba.Issho.tools() ++ Hakushi.Issho.tools() ++ Masu.Issho.tools() ++ Fude.Issho.tools()
  end

  @doc """
  The scope of the person an agent works for (`on_behalf_of`, from the
  token it connected with), or nil. The agent may do what they may.
  """
  def scope(%Issho.Tool.Context{opts: opts}) do
    with %{} = person <- opts[:on_behalf_of],
         key = Issho.Identity.new(person).key,
         {id, ""} <- Integer.parse(key),
         %Notebook.Accounts.User{} = user <- Notebook.Repo.get(Notebook.Accounts.User, id) do
      Notebook.Accounts.Scope.for_user(user)
    else
      _ -> nil
    end
  end

  @doc "A page as an agent reads it: what it is, where it is, and the names its tools take."
  def describe(%Notebook.Pages.Page{} = page) do
    page = Notebook.Repo.preload(page, [:space, :folder])
    room = Notebook.Collaboration.room(page)

    %{
      "id" => page.id,
      "title" => page.title,
      "kind" => page.kind,
      "space" => page.space && page.space.name,
      "folder" => page.folder && page.folder.name,
      "room" => room,
      "url" => NotebookWeb.Endpoint.url() <> "/pages/#{page.id}",
      "use" =>
        case page.kind do
          "board" ->
            %{"canvas" => room, "tools" => "read_canvas, add_node, move_node, connect_nodes, ..."}

          "table" ->
            %{"grid" => room <> "/rows", "tools" => "read_grid, edit_cells, add_rows, ..."}

          "database" ->
            %{"page_id" => page.id, "tools" => "read_database, add_records, update_records"}

          _text ->
            %{
              "document" => room <> "/body",
              "tools" => "read_text, select_text, type_text, ...",
              "charts" =>
                for chart <- Notebook.Repo.all(Ecto.assoc(page, :charts)) do
                  %{
                    "chart" => Notebook.Charts.document(chart),
                    "title" => chart.spec["title"],
                    "tools" => "read_chart, change_chart"
                  }
                end
            }
        end
    }
  end
end

defmodule Notebook.Tools.ListPages do
  @moduledoc false
  use Issho.Tool,
    name: "list_pages",
    description: """
    The Notebook's pages that the person you work for may read: each
    one's title, kind (a text, a board, a table or a database), its space
    and folder, its room, and the name its tools take: a text's document
    for Kotoba's tools (read_text, type_text...), a board's canvas for
    Hakushi's (read_canvas, add_node...), a table's grid for Masu's
    (read_grid, edit_cells...), a database's page id for read_database,
    add_records and update_records. Start here.
    """,
    annotations: [read_only: true, idempotent: true]

  arg(:search, :string,
    description:
      "Words of a title, a text, a table's rows or a database's records: the best first"
  )

  arg(:space, :string, description: "Only the pages of the space of this name")

  @impl true
  def call(args, ctx) do
    case Notebook.Tools.scope(ctx) do
      nil ->
        {:error, "Pages are read for a person: connect as one (see the Notebook's Agents page)."}

      scope ->
        pages =
          scope
          |> Notebook.Pages.list(search: args[:search] || "")
          |> Enum.filter(&(is_nil(args[:space]) or &1.space.name == args[:space]))

        {:ok, %{"pages" => Enum.map(pages, &Notebook.Tools.describe/1)}}
    end
  end
end

defmodule Notebook.Tools.CreatePage do
  @moduledoc false
  use Issho.Tool,
    name: "create_page",
    description: """
    Makes a page: a text, a board (notes and arrows), a table (rows of
    tasks) or a database (records with fields: a Name, a Status, an
    Owner, a Due day and Tags to start), with a title, by the person you work for, in a space they may
    edit (their Private space when you name none). Gives the page, and
    the name its tools take.
    """,
    annotations: []

  arg(:title, :string, required: true, max_length: 160)
  arg(:kind, {:enum, ["text", "board", "table", "database"]}, required: true)
  arg(:space, :string, description: "The name of the space, as list_pages gives it")

  alias Notebook.Spaces

  @impl true
  def call(%{title: title, kind: kind} = args, ctx) do
    with scope when not is_nil(scope) <- Notebook.Tools.scope(ctx),
         {:ok, space} <- space(scope, args[:space]),
         {:ok, page} <-
           Notebook.Pages.create(scope, %{
             "title" => title,
             "kind" => kind,
             "space_id" => space.id
           }) do
      {:ok, Notebook.Tools.describe(page)}
    else
      nil ->
        {:error, "A page is made for a person: connect as one (see the Notebook's Agents page)."}

      {:error, :no_space} ->
        {:error, "No space of that name: list_pages gives each page's space."}

      {:error, %Sekisho.Denied{}} ->
        {:error, "The person you work for may not make pages in that space."}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, inspect(changeset.errors)}
    end
  end

  defp space(scope, nil), do: {:ok, Spaces.private!(scope.user)}

  defp space(scope, name) do
    case Enum.find(Spaces.list(scope), &(&1.name == name)) do
      nil -> {:error, :no_space}
      space -> {:ok, space}
    end
  end
end
