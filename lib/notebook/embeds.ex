defmodule Notebook.Embeds do
  @moduledoc """
  What a text's embeds are outside the editor (its Markdown, the page that
  reads it): a table is a snapshot of its rows, which Markdown viewers
  draw; a board is its title, as Kotoba writes it.
  """

  alias Notebook.Pages.Page

  @doc "An embed as Markdown or HTML (`Kotoba.Renderer`'s `:embed`), or `nil` for Kotoba's own."
  def render(%{kind: "table", ref: ref}, format) when format in [:markdown, :html] do
    with {id, ""} <- Integer.parse(to_string(ref)),
         %Page{kind: "table"} = page <- Notebook.Pages.get(id) do
      sheet = Masu.Sheet.new(Notebook.Grids.rows(page))

      case format do
        :markdown -> Masu.Snapshot.markdown(sheet, rows: 20)
        :html -> Masu.Snapshot.html(sheet, rows: 20)
      end
    else
      _other -> nil
    end
  end

  def render(_embed, _format), do: nil
end
