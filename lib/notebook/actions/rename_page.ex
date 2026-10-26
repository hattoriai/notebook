defmodule Notebook.Actions.RenamePage do
  @moduledoc false
  use Issho.Action,
    name: "rename_page",
    description: """
    Renames a page, as the person you work for (they edit it). Gives its
    new title.
    """

  arg(:page_id, :integer, required: true, description: "The page, as list_pages gives it")
  arg(:title, :string, required: true, min_length: 1, max_length: 160)

  alias Notebook.Actions

  @impl Issho.Action
  def target(%{page_id: id}), do: Actions.room(id)

  @impl Issho.Action
  def run(%{page_id: id, title: title}, invocation) do
    with {:ok, scope, page} <- Actions.page(id, invocation) do
      case Notebook.Pages.update(scope, page, %{"title" => title}) do
        {:ok, page} -> {:ok, page}
        {:error, reason} -> {:error, Actions.error(reason)}
      end
    end
  end

  @impl Issho.Action
  def summary(page), do: "Renamed: #{page.title}."

  @impl Issho.Action
  def event(%{page_id: id}, page), do: %{page: id, title: page.title}
end
