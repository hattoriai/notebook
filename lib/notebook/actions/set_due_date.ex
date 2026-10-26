defmodule Notebook.Actions.SetDueDate do
  @moduledoc false
  use Issho.Action,
    name: "set_due_date",
    description: """
    Gives a page a due date, or takes it away, as the person you work for
    (they edit it). The page shows it, the calendar lists it, and its
    people are reminded.
    """

  arg(:page_id, :integer, required: true, description: "The page, as list_pages gives it")

  arg(:due, :string,
    required: true,
    max_length: 10,
    description: ~s(A day, "2026-11-02"; or "none" to take the due date away)
  )

  alias Notebook.Actions

  @impl Issho.Action
  def target(%{page_id: id}), do: Actions.room(id)

  @impl Issho.Action
  def run(%{page_id: id, due: due}, invocation) do
    with {:ok, scope, page} <- Actions.page(id, invocation),
         {:ok, day} <- day(due) do
      case Notebook.Pages.update(scope, page, %{"due_on" => day}) do
        {:ok, page} -> {:ok, page}
        {:error, reason} -> {:error, Actions.error(reason)}
      end
    end
  end

  defp day("none"), do: {:ok, nil}

  defp day(text) do
    case Date.from_iso8601(text) do
      {:ok, day} -> {:ok, day}
      {:error, _} -> {:error, ~s(Give the day as 2026-11-02, or "none".)}
    end
  end

  @impl Issho.Action
  def summary(%{due_on: nil, title: title}), do: "#{title} has no due date now."
  def summary(%{due_on: day, title: title}), do: "#{title} is due on #{Date.to_iso8601(day)}."

  @impl Issho.Action
  def event(%{page_id: id}, page),
    do: %{page: id, due: page.due_on && Date.to_iso8601(page.due_on)}
end
