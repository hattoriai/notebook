defmodule Notebook.Boards do
  @moduledoc """
  The boards of board pages: a Hakushi canvas where a plan takes shape.
  Its pieces, in the Notebook's own hand:

    * `title`: the board's name and what it is about, on the paper;
    * `card`: an index card, a kicker in small capitals over a line of
      text, and a footnote;
    * `note`: a note in one of the notebook's tones;
    * `page`: another page of the notebook, which opens from the board;
    * `frame`: a part of the plan that holds cards and notes.

  Arrows carry a word ("then", "needs"). The graph is kept on the page,
  saved with each change (the canvas's `on_change`), whoever makes it: a
  person in a browser, or an agent.
  """
  import Ecto.Query, only: [from: 2]

  alias Hakushi.Graph
  alias Notebook.Pages.Page
  alias Notebook.Repo

  @tones ~w(ochre clay sage sky)

  @doc "The tones of the notes."
  def tones, do: @tones

  @doc "The board of a page, as it was last saved, or a first one."
  def graph(%Page{board: nil} = page), do: first(page)
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

  @doc "A new piece, where a person drops one, or double-clicks the paper."
  def new_node("frame", {x, y}),
    do: %{
      type: "frame",
      x: x,
      y: y,
      width: 420,
      height: 300,
      data: %{"title" => "A part of the plan"}
    }

  def new_node("note", {x, y}),
    do: %{
      type: "note",
      x: x,
      y: y,
      width: 220,
      height: 130,
      data: %{"tone" => "ochre", "text" => "A thought"}
    }

  def new_node(_card, {x, y}),
    do: %{
      type: "card",
      x: x,
      y: y,
      data: %{"kicker" => "Step", "text" => "What comes next", "foot" => nil}
    }

  # A board that shows what a board is for: the plan of the forge.
  defp first(%Page{} = page) do
    table = Repo.one(from p in Page, where: p.kind == "table", order_by: p.id, limit: 1)

    nodes =
      [
        %{
          id: "title",
          type: "title",
          x: 0,
          y: -150,
          data: %{
            "text" => page.title,
            "sub" => "From the steel to the ceremony · a plan to share"
          }
        },
        %{
          id: "forging",
          type: "frame",
          x: 0,
          y: 0,
          width: 760,
          height: 220,
          data: %{"title" => "Forging"}
        },
        card(
          "steel",
          30,
          50,
          "Step 1",
          "Choose the steel",
          "Tamahagane, from the river sand",
          "forging"
        ),
        card(
          "fold",
          280,
          50,
          "Step 2",
          "Fold it, again and again",
          "Sixteen times, no fewer",
          "forging"
        ),
        card(
          "clay",
          530,
          50,
          "Step 3",
          "Temper with clay",
          "Thin on the edge, thick on the spine",
          "forging"
        ),
        %{
          id: "finishing",
          type: "frame",
          x: 0,
          y: 300,
          width: 510,
          height: 220,
          data: %{"title" => "Finishing"}
        },
        card(
          "polish",
          30,
          350,
          "Step 4",
          "Polish the edge",
          "Eight stones, coarse to fine",
          "finishing"
        ),
        card("handle", 280, 350, "Step 5", "Wrap the handle", "Ray skin, then silk", "finishing"),
        note("ask", 860, 40, "ochre", "Ask Masamune about the clay mix before we start."),
        note(
          "rest",
          600,
          360,
          "sage",
          "Let the blade rest a day between the quench and the polish."
        )
      ] ++ if(table, do: [page_card("tasks", 860, 330, table)], else: [])

    edges =
      [
        %{id: "e1", source: "steel", target: "fold", label: "then", path: "smooth"},
        %{id: "e2", source: "fold", target: "clay", label: "then", path: "smooth"},
        %{id: "e3", source: "clay", target: "polish", label: "then", path: "smooth"},
        %{id: "e4", source: "polish", target: "handle", label: "then", path: "smooth"},
        %{id: "e5", source: "ask", target: "clay", label: "before", path: "bezier", marker: "dot"}
      ] ++
        if(table,
          do: [
            %{id: "e6", source: "handle", target: "tasks", label: "tracked in", path: "bezier"}
          ],
          else: []
        )

    Graph.new(nodes: nodes, edges: edges)
  end

  defp card(id, x, y, kicker, text, foot, parent),
    do: %{
      id: id,
      type: "card",
      x: x,
      y: y,
      parent: parent,
      data: %{"kicker" => kicker, "text" => text, "foot" => foot}
    }

  defp note(id, x, y, tone, text),
    do: %{
      id: id,
      type: "note",
      x: x,
      y: y,
      width: 220,
      height: 120,
      data: %{"tone" => tone, "text" => text}
    }

  defp page_card(id, x, y, %Page{} = page),
    do: %{
      id: id,
      type: "page",
      x: x,
      y: y,
      data: %{"page" => page.id, "title" => page.title, "kind" => page.kind}
    }
end
