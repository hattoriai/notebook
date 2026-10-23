defmodule Notebook.IsshoStore do
  @moduledoc """
  Where Issho keeps its own documents of the Notebook (`Issho.Store`):
  each page's comments, the agents' inboxes, the shared state of the
  notebook, in `issho_documents`. A page's text, board and table keep
  theirs elsewhere (`Notebook.CollabStore`, the pages, the rows).
  """
  @behaviour Issho.Store

  import Ecto.Query

  alias Notebook.IsshoStore.Document

  @impl true
  def load(repo, id) do
    case repo.get(Document, id) do
      nil -> {:ok, nil}
      %Document{document: document} -> {:ok, document}
    end
  end

  @impl true
  def save(repo, id, expected, document, content) do
    values = [
      epoch: document["epoch"],
      revision: document["revision"],
      document: document,
      # A map column: the content may be any JSON value.
      content: %{"value" => content}
    ]

    result =
      case expected do
        nil ->
          repo.insert_all(Document, [Map.new([id: id] ++ values)], on_conflict: :nothing)

        {epoch, revision} ->
          from(d in Document,
            where: d.id == ^id and d.epoch == ^epoch and d.revision == ^revision
          )
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
