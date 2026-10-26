defmodule Notebook.Tools do
  @moduledoc """
  What an agent can do in the Notebook, however it connects: the tools
  of the pages' rooms (Issho's), of their parts (Kotoba's text, Hakushi's
  board, Masu's table, Fude's charts), and the Notebook's own: to find the
  pages, to make one, to read and write a database's records
  (`Notebook.Tools.Databases`), and its own memory (`Notebook.Tools.Memory`);
  and what a person does on a page too, by the same way
  (`Notebook.Actions`: rename it, give it a due date, add records).
  """

  @doc "Every tool of the Notebook, for MCP (NotebookWeb.MCP) or an app's own model."
  def all do
    [Notebook.Tools.ListPages, Notebook.Tools.Memory, Notebook.Tools.ReadDatabase] ++
      Notebook.Actions.all() ++
      Issho.Tools.room() ++
      Kotoba.Issho.tools() ++ Hakushi.Issho.tools() ++ Masu.Issho.tools() ++ Fude.Issho.tools()
  end

  @doc """
  The scope of the person an agent works for (`on_behalf_of`, from the
  token it connected with), as their agent, or nil. The agent may do what
  they may, but not on what is off limits to agents.
  """
  def scope(%Issho.Tool.Context{opts: opts} = ctx) do
    with %{} = person <- opts[:on_behalf_of],
         key = Issho.Identity.new(person).key,
         {id, ""} <- Integer.parse(key),
         %Notebook.Accounts.User{} = user <- Notebook.Repo.get(Notebook.Accounts.User, id) do
      Notebook.Accounts.Scope.for_agent(user, Issho.Identity.new(ctx.actor).key)
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
      "space_id" => page.space_id,
      "folder" => page.folder && page.folder.name,
      "room" => room,
      "url" => NotebookWeb.Endpoint.url() <> "/pages/#{page.id}",
      "due" => page.due_on && Date.to_iso8601(page.due_on),
      "page_tools" => "rename_page, set_due_date, move_page, archive_page, restore_page",
      "use" =>
        case page.kind do
          "board" ->
            %{"canvas" => room, "tools" => "read_canvas, add_node, move_node, connect_nodes, ..."}

          "table" ->
            %{"grid" => room <> "/rows", "tools" => "read_grid, edit_cells, add_rows, ..."}

          "database" ->
            %{
              "page_id" => page.id,
              "tools" =>
                "read_database, add_records, update_records, delete_records, move_record, add_field, add_view"
            }

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
    add_records and update_records; and the spaces they may make pages in
    (create_page's space_id). Start here.
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

        {:ok,
         %{
           "pages" => Enum.map(pages, &Notebook.Tools.describe/1),
           "spaces" => spaces(scope)
         }}
    end
  end

  # The spaces the person may make pages in (create_page's space_id).
  defp spaces(scope) do
    for space <- Notebook.Spaces.list(scope),
        Notebook.Permissions.allowed?(scope, :edit, space),
        do: %{"id" => space.id, "name" => space.name}
  end
end
