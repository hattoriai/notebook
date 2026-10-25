defmodule Notebook.Charts.Chart do
  @moduledoc """
  A chart in a text page: a Fude spec (`Fude.Spec.dump/1`), drawn from
  the rows of a table page, its source.
  """
  use Ecto.Schema

  schema "charts" do
    field :spec, :map
    belongs_to :page, Notebook.Pages.Page
    belongs_to :source, Notebook.Pages.Page
    timestamps(type: :utc_datetime)
  end
end
