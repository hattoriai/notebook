# A scripted agent: an MCP client of the Notebook, as Claude Code or Codex
# is, that works on the pages through their tools. For a demo without a
# model, and for trying the Notebook's MCP endpoint.
#
#     mix run --no-start scripts/agent.exs "http://localhost:4000/mcp?token=..." board "The forge, planned"
#
# What it does: on a board, adds cards and joins them; on a table, edits
# cells and adds a row; on a text, types a line; `selected`, on a text,
# makes bold what a person has selected there (OF=name, Hattori Hanzo
# unless given). Open the page in a
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
    {_, session} = call.(session, "set_status", %{"room" => page["room"], "status" => "Planning the ceremony"})

    {ids, session} =
      Enum.reduce(
        [{"Step 6", "Name the blade", 30, 640}, {"Step 7", "Present it at dawn", 280, 640}],
        {[], session},
        fn {kicker, text, x, y}, {ids, session} ->
          {%{"id" => id}, session} =
            call.(session, "add_node", %{
              "canvas" => canvas,
              "type" => "card",
              "x" => x,
              "y" => y,
              "data" => %{"kicker" => kicker, "text" => text, "foot" => "Added by the agent"}
            })

          {ids ++ [id], session}
        end
      )

    [name, present] = ids
    {_, session} = call.(session, "connect_nodes", %{"canvas" => canvas, "source" => "handle", "target" => name, "label" => "then"})
    {_, session} = call.(session, "connect_nodes", %{"canvas" => canvas, "source" => name, "target" => present, "label" => "then"})
    {_, _session} = call.(session, "move_node", %{"canvas" => canvas, "node" => present, "x" => 530, "y" => 640})

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

  "selected" ->
    # What a person of the page has selected: the agent reads it, and
    # makes it bold and highlighted, there.
    document = page["use"]["document"]
    who = System.get_env("OF", "Hattori Hanzo")
    {_, session} = call.(session, "set_status", %{"room" => page["room"], "status" => "Looking at what #{who} selected"})
    {%{"selected" => %{"text" => text}}, session} = call.(session, "read_text", %{"document" => document, "of" => who})
    IO.puts("#{who} selected: #{inspect(text)}")

    {_, _session} =
      call.(session, "format_text", %{
        "document" => document,
        "of" => who,
        "marks" => %{"bold" => true, "highlight" => true}
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
