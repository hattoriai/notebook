defmodule Notebook.Actions.SetAgents do
  @moduledoc false
  # Whether agents may work on a page. A person's only, from the Share
  # dialog: what agents may reach is their people's to say.
  use Issho.Action,
    name: "set_agents",
    description: "Closes a page to agents, or opens it to them again."

  arg(:page_id, :integer, required: true)
  arg(:closed, :boolean, required: true)

  alias Notebook.Actions

  @impl Issho.Action
  def target(%{page_id: id}), do: Actions.room(id)

  @impl Issho.Action
  def authorize(_args, who), do: Actions.person_only(who)

  @impl Issho.Action
  def run(%{page_id: id, closed: closed}, invocation) do
    with {:ok, scope, page} <- Actions.page(id, invocation) do
      case Notebook.Pages.set_closed_to_agents(scope, page, closed) do
        {:ok, page} -> {:ok, page}
        {:error, reason} -> {:error, Actions.error(reason)}
      end
    end
  end

  @impl Issho.Action
  def event(%{page_id: id, closed: closed}, _page), do: %{page: id, closed: closed}
end
