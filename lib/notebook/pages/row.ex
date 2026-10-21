defmodule Notebook.Pages.Row do
  @moduledoc "A row of a table page: a task, its status, who has it, when it is due."
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(todo doing done)

  schema "page_rows" do
    field :title, :string
    field :status, :string, default: "todo"
    field :owner, :string
    field :due_on, :date
    field :points, :integer
    belongs_to :page, Notebook.Pages.Page
    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(row, params) do
    row
    |> cast(params, [:title, :status, :owner, :due_on, :points])
    |> validate_required([:title])
    |> validate_length(:title, max: 200)
    |> validate_length(:owner, max: 80)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:points, greater_than_or_equal_to: 0, less_than: 1000)
  end
end
