defmodule Notebook.Actions.MovePage do
  @moduledoc false
  use Issho.Action,
    name: "move_page",
    description: """
    Moves a page to another space, or a folder of it, as the person you
    work for (they edit the page and the space).
    """

  arg(:page_id, :integer, required: true, description: "The page, as list_pages gives it")
  arg(:space_id, :integer, required: true, description: "The space it goes to")
  arg(:folder_id, :integer, description: "A folder of that space; none for its top")

  alias Notebook.Actions

  @impl Issho.Action
  def target(%{page_id: id}), do: Actions.room(id)

  @impl Issho.Action
  def run(%{page_id: id, space_id: space_id} = args, invocation) do
    with {:ok, scope, page} <- Actions.page(id, invocation) do
      case Notebook.Pages.move(scope, page, space_id, args[:folder_id]) do
        {:ok, page} -> {:ok, page}
        {:error, _reason} -> {:error, "You may not move this page there."}
      end
    end
  end

  @impl Issho.Action
  def summary(page), do: "Moved #{page.title} to #{place(page)}."

  @impl Issho.Action
  def event(%{page_id: id}, page), do: %{page: id, to: place(page)}

  @doc false
  def place(%{space: space, folder: nil}), do: space.name
  def place(%{space: space, folder: folder}), do: "#{space.name} / #{folder.name}"
end
