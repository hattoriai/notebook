defmodule Notebook.Actions.CreatePage do
  @moduledoc false
  use Issho.Action,
    name: "create_page",
    description: """
    Makes a page: a text, a board (notes and arrows), a table (rows of
    tasks) or a database (records with fields: a Name, a Status, an Owner,
    a Due day and Tags to start), with a title, by the person you work
    for, in a space they may edit (space_id: list_pages gives the spaces,
    their Private one among them), in its folder if you give one. Gives
    the page, and the name its tools take.
    """

  arg(:title, :string, required: true, min_length: 1, max_length: 160)
  arg(:kind, {:enum, ["text", "board", "table", "database"]}, required: true)
  arg(:space_id, :integer, required: true, description: "The space, as list_pages gives it")
  arg(:folder_id, :integer, description: "A folder of that space")
  arg(:due_on, :string, max_length: 10, description: ~s(A due day, "2026-11-02"))
  arg(:details, :any, description: "The new page form's other fields (a person's)")

  alias Notebook.{Actions, Pages}

  @impl Issho.Action
  def target(%{space_id: id}), do: "space:#{id}"

  @impl Issho.Action
  def run(args, invocation) do
    with {:ok, scope} <- Actions.scope(invocation) do
      attrs =
        (args[:details] || %{})
        |> Map.new(fn {key, value} -> {to_string(key), value} end)
        |> Map.take(~w(covers review_at revisit))
        |> Map.merge(%{
          "title" => args.title,
          "kind" => args.kind,
          "space_id" => args.space_id,
          "folder_id" => args[:folder_id],
          "due_on" => args[:due_on]
        })

      case Pages.create(scope, attrs) do
        {:ok, page} -> {:ok, page}
        {:error, %Sekisho.Denied{}} -> {:error, "You may not make pages in that space."}
        {:error, :no_space} -> {:error, "No such space: list_pages gives each page's."}
        {:error, reason} -> {:error, Actions.error(reason)}
      end
    end
  end

  @impl Issho.Action
  def summary(page), do: Notebook.Tools.describe(page)

  @impl Issho.Action
  def event(_args, page), do: %{page: page.id, title: page.title, kind: page.kind}
end
