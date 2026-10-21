defmodule Notebook.Boards do
  @moduledoc """
  The boards of board pages: a Hakushi canvas of notes, joined by arrows.
  Its graph is kept on the page, saved with each change (the canvas's
  `on_change`), whoever makes it: a person in a browser, or an agent.
  """
  import Ecto.Query

  alias Hakushi.Graph
  alias Notebook.Pages.Page
  alias Notebook.Repo

  @colors ~w(#f6e7a8 #f3c7b6 #cfe3c3 #c9dbe8 #e2d1ec)

  @doc "The colors of the notes."
  def colors, do: @colors

  @doc "The board of a page, as it was last saved, or a first one."
  def graph(%Page{board: nil}), do: first()
  def graph(%Page{board: board}), do: Graph.load(board)

  @doc """
  Saves a page's board, after each change of its canvas. The canvas's
  `on_change`: it answers `:ok`, so the change goes to everyone.
  """
  def on_change(page_id) do
    fn _change, %{result: result} ->
      from(p in Page, where: p.id == ^page_id)
      |> Repo.update_all(set: [board: Graph.dump(result), updated_at: DateTime.utc_now(:second)])

      :ok
    end
  end

  @doc "A new note, where a person drops one."
  def new_node("note", {x, y}),
    do: %{type: "note", x: x, y: y, data: %{"text" => "A new note", "color" => hd(@colors)}}

  def new_node(_item, _place), do: nil

  defp first do
    Graph.new(
      nodes: [
        note("idea", 0, 0, "Start with a question", 0),
        note("why", 260, -40, "Why does it matter?", 1),
        note("next", 260, 120, "What do we try first?", 2)
      ],
      edges: [
        %{id: "e1", source: "idea", target: "why"},
        %{id: "e2", source: "idea", target: "next"}
      ]
    )
  end

  defp note(id, x, y, text, color),
    do: %{
      id: id,
      type: "note",
      x: x,
      y: y,
      data: %{"text" => text, "color" => Enum.at(@colors, color)}
    }
end
