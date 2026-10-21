# A scripted agent: an MCP client of the Notebook, as Claude Code or Codex
# is, that works on the pages through their tools. For a demo without a
# model, and for trying the Notebook's MCP endpoint.
#
#     mix run --no-start scripts/agent.exs "http://localhost:4000/mcp?token=..." board "The forge, planned"
#
# What it does: on a board, adds notes and joins them; on a table, edits
# cells and adds a row; on a text, types a line. Open the page in a
# browser first, to watch it work.

{:ok, _apps} = Application.ensure_all_started([:req, :sake])

[url, kind, title] = System.argv()

{:ok, session} =
  Sake.Client.connect(url, client_info: %{"name" => "notebook-agent", "title" => "Scripted agent"})

call = fn session, tool, args ->
  case Sake.Client.call_tool(session, tool, args) do
    {:ok, %{is_error: true, text: text}, _session} -> raise "#{tool}: #{text}"
    {:ok, result, session} -> {result.structured || result.text, session}
  end
end

{%{"pages" => pages}, session} = call.(session, "list_pages", %{"search" => title})
page = Enum.find(pages, &(&1["title"] == title)) || raise "There is no page #{inspect(title)}."
IO.puts("Working on #{page["title"]} (#{page["kind"]}, #{page["room"]})")

{_, session} = call.(session, "join_room", %{"room" => page["room"]})

case kind do
  "board" ->
    canvas = page["use"]["canvas"]
    {_, session} = call.(session, "set_status", %{"room" => page["room"], "status" => "Planning the forge"})

    {ids, session} =
      Enum.reduce(
        [{"Choose the steel", 0, 240}, {"Fold it, again and again", 260, 240}, {"Temper with clay", 520, 240}],
        {[], session},
        fn {text, x, y}, {ids, session} ->
          {%{"id" => id}, session} =
            call.(session, "add_node", %{
              "canvas" => canvas,
              "type" => "note",
              "x" => x,
              "y" => y,
              "data" => %{"text" => text, "color" => "#cfe3c3"}
            })

          {ids ++ [id], session}
        end
      )

    session =
      ids
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.reduce(session, fn [a, b], session ->
        {_, session} = call.(session, "connect_nodes", %{"canvas" => canvas, "source" => a, "target" => b})
        session
      end)

    {_, _session} = call.(session, "move_node", %{"canvas" => canvas, "node" => List.last(ids), "x" => 560, "y" => 120})

  "table" ->
    grid = page["use"]["grid"]
    {_, session} = call.(session, "set_status", %{"room" => page["room"], "status" => "Updating the blades"})
    {%{"rows" => rows}, session} = call.(session, "read_grid", %{"grid" => grid})

    edits =
      for row <- rows, row["owner"] in [nil, ""],
          do: %{"row" => row["id"], "key" => "owner", "value" => "Masamune"}

    edits =
      edits ++ for(row <- rows, row["status"] == "doing", do: %{"row" => row["id"], "key" => "status", "value" => "done"})

    {_, session} = call.(session, "edit_cells", %{"grid" => grid, "edits" => edits})

    {_, _session} =
      call.(session, "add_rows", %{
        "grid" => grid,
        "rows" => [%{"title" => "Sharpen for the ceremony", "status" => "todo", "owner" => "Hanzo", "points" => 3}]
      })

  "text" ->
    document = page["use"]["document"]
    {_, session} = call.(session, "set_status", %{"room" => page["room"], "status" => "Writing a summary"})

    {_, session} =
      call.(session, "add_block", %{"document" => document, "after" => 0, "type" => "h2", "text" => "In short"})

    {_, _session} =
      call.(session, "type_text", %{
        "document" => document,
        "after" => "In short",
        "text" => " — a notebook where people and agents write, plan and track together."
      })
end

IO.puts("Done.")
