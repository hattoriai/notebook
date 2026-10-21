defmodule Notebook.Tools do
  @moduledoc """
  What an agent can do in the Notebook, however it connects: the tools
  of the pages' rooms (Issho's), of their parts (Kotoba's text, Hakushi's
  board, Masu's table), and the Notebook's own, to find the pages and to
  make one.
  """

  @doc "Every tool of the Notebook, for MCP (NotebookWeb.MCP) or an app's own model."
  def all do
    [Notebook.Tools.ListPages, Notebook.Tools.CreatePage] ++
      Issho.Tools.room() ++ Kotoba.Issho.tools() ++ Hakushi.Issho.tools() ++ Masu.Issho.tools()
  end

  @doc "A page as an agent reads it: what it is, and the names its tools take."
  def describe(%Notebook.Pages.Page{} = page) do
    room = Notebook.Collaboration.room(page)

    %{
      "id" => page.id,
      "title" => page.title,
      "kind" => page.kind,
      "room" => room,
      "url" => NotebookWeb.Endpoint.url() <> "/pages/#{page.id}",
      "use" =>
        case page.kind do
          "board" ->
            %{"canvas" => room, "tools" => "read_canvas, add_node, move_node, connect_nodes, ..."}

          "table" ->
            %{"grid" => room <> "/rows", "tools" => "read_grid, edit_cells, add_rows, ..."}

          _text ->
            %{"document" => room <> "/body", "tools" => "read_text, select_text, type_text, ..."}
        end
    }
  end
end

defmodule Notebook.Tools.ListPages do
  @moduledoc false
  use Issho.Tool,
    name: "list_pages",
    description: """
    The Notebook's pages: each one's title, kind (a text, a board or a
    table), its room, and the name its tools take: a text's document for
    Kotoba's tools (read_text, type_text...), a board's canvas for
    Hakushi's (read_canvas, add_node...), a table's grid for Masu's
    (read_grid, edit_cells...). Start here.
    """,
    annotations: [read_only: true, idempotent: true]

  arg(:search, :string, description: "Words of a title or a text")

  @impl true
  def call(args, _ctx),
    do:
      {:ok,
       %{
         "pages" => Enum.map(Notebook.Pages.list(args[:search] || ""), &Notebook.Tools.describe/1)
       }}
end

defmodule Notebook.Tools.CreatePage do
  @moduledoc false
  use Issho.Tool,
    name: "create_page",
    description: """
    Makes a page: a text, a board (notes and arrows) or a table (rows of
    tasks), with a title, by the person you work for. Gives the page, and
    the name its tools take.
    """,
    annotations: []

  arg(:title, :string, required: true, max_length: 160)
  arg(:kind, {:enum, ["text", "board", "table"]}, required: true)

  alias Notebook.Accounts.{Scope, User}

  @impl true
  def call(%{title: title, kind: kind}, ctx) do
    with %User{} = user <- person(ctx),
         {:ok, page} <-
           Notebook.Pages.create(Scope.for_user(user), %{"title" => title, "kind" => kind}) do
      {:ok, Notebook.Tools.describe(page)}
    else
      nil ->
        {:error, "A page is made for a person: connect as one (see the Notebook's Agents page)."}

      {:error, changeset} ->
        {:error, inspect(changeset.errors)}
    end
  end

  defp person(%Issho.Tool.Context{opts: opts}) do
    with %{} = person <- opts[:on_behalf_of],
         key = Issho.Identity.new(person).key,
         {id, ""} <- Integer.parse(key) do
      Notebook.Repo.get(User, id)
    else
      _ -> nil
    end
  end
end
