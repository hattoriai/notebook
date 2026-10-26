defmodule Notebook.Actions.RestorePage do
  @moduledoc false
  use Issho.Action,
    name: "restore_page",
    description:
      "Brings an archived page back to its place, as the person you work for (they edit it)."

  arg(:page_id, :integer, required: true, description: "The page, as list_pages gives it")

  alias Notebook.Actions

  @impl Issho.Action
  def target(%{page_id: id}), do: Actions.room(id)

  @impl Issho.Action
  def run(%{page_id: id}, invocation) do
    with {:ok, scope, page} <- Actions.page(id, invocation) do
      case Notebook.Pages.restore(scope, page) do
        {:ok, page} -> {:ok, Notebook.Repo.preload(page, [:space, :folder], force: true)}
        {:error, reason} -> {:error, Actions.error(reason)}
      end
    end
  end

  @impl Issho.Action
  def summary(page), do: "Restored #{page.title}."

  @impl Issho.Action
  def event(%{page_id: id}, _page), do: %{page: id}
end
