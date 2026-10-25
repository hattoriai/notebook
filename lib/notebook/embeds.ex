defmodule Notebook.Embeds do
  @moduledoc """
  What a text's embeds are outside the editor (its Markdown, the page that
  reads it): a table is a snapshot of its rows, which Markdown viewers
  draw; a board is its title, as Kotoba writes it.

  An embed's ref is the writer's input: the table is drawn only for a
  reader who may read its page, and is its title for anyone else.
  """

  alias Notebook.Pages.Page

  @doc "The function Kotoba renders a reader's embeds with (`:embed`)."
  def renderer(scope), do: &render(scope, &1, &2)

  @doc "An embed as Markdown or HTML (`Kotoba.Renderer`'s `:embed`), or `nil` for Kotoba's own."
  def render(scope, %{kind: "table", ref: ref}, format) when format in [:markdown, :html] do
    with {id, ""} <- Integer.parse(to_string(ref)),
         %Page{kind: "table"} = page <- Notebook.Pages.get(scope, id) do
      sheet = Masu.Sheet.new(Notebook.Grids.rows(page))

      case format do
        :markdown -> Masu.Snapshot.markdown(sheet, rows: 20)
        :html -> Masu.Snapshot.html(sheet, rows: 20)
      end
    else
      _other -> nil
    end
  end

  def render(_scope, _embed, _format), do: nil
end
