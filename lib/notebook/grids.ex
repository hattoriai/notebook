defmodule Notebook.Grids do
  @moduledoc """
  The table of a table page, defined once: the attributes of its
  `<.data_grid>` in the LiveView, and of its `Masu.Sheet` for an agent,
  whose writes go the grid's way (the changeset, the conflicts, the live
  rows of everyone who has it open).
  """
  import Ecto.Query

  alias Notebook.Pages.{Page, Row}
  alias Notebook.Repo

  @doc "The grid of a table page."
  def rows(%Page{id: id}) do
    [
      id: "rows",
      source: from(r in Row, where: r.page_id == ^id, order_by: r.id),
      repo: Repo,
      changeset: &Row.changeset/2,
      struct: %Row{},
      create_with: %{page_id: id},
      deletable: true,
      live: {Notebook.PubSub, "page-rows:#{id}"},
      columns: [
        [field: :title, width: 320],
        [field: :status, type: :enum, values: Row.statuses(), width: 120],
        [field: :owner, width: 160],
        [field: :due_on, type: :date, label: "Due", width: 140],
        [field: :points, type: :integer, width: 100]
      ]
    ]
  end

  @doc """
  The grid an agent names, `"page:<id>/rows"` (Masu.Issho): a table page's,
  for whoever may be in its room (the room's policy asks).
  """
  def for_agent("page:" <> rest, _ctx) do
    with [id, "rows"] <- String.split(rest, "/"),
         {id, ""} <- Integer.parse(id),
         %Page{kind: "table"} = page <- Repo.get(Page, id) do
      {:ok, rows(page)}
    else
      _ -> {:error, "There is no such table: name a table page's grid, page:<id>/rows."}
    end
  end

  def for_agent(_grid, _ctx), do: {:error, "Name a table page's grid: page:<id>/rows."}
end
