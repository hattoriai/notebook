defmodule Notebook.CollabStore do
  @moduledoc """
  The shared text of each page (`"page:<id>/body"`): its accepted state
  and content, in `collab_drafts`. A page with no draft starts from its
  published body.
  """
  @behaviour Kotoba.Collab.Store
  import Ecto.Query
  alias Notebook.CollabStore.Draft
  alias Notebook.Pages

  @impl true
  def load(repo, id) do
    page_id = Notebook.Collaboration.page_id(id)
    page = if page_id, do: Pages.fetch(page_id)

    case {page, repo.get(Draft, id)} do
      {nil, _} -> {:error, :not_found}
      {page, nil} -> {:ok, %{state: nil, content: page.body || Kotoba.Content.empty()}}
      {_, draft} -> {:ok, %{state: draft.state, content: draft.content}}
    end
  end

  @impl true
  def save(repo, id, expected, state, content) do
    values = [epoch: state["epoch"], revision: state["revision"], state: state, content: content]

    result =
      case expected do
        nil ->
          repo.insert_all(Draft, [Map.new([id: id] ++ values)], on_conflict: :nothing)

        {epoch, revision} ->
          from(d in Draft, where: d.id == ^id and d.epoch == ^epoch and d.revision == ^revision)
          |> repo.update_all(set: values)
      end

    case result do
      {1, _} -> :ok
      {0, _} -> {:error, :conflict}
    end
  rescue
    error -> {:error, error}
  end
end
