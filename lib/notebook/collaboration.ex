defmodule Notebook.Collaboration do
  @moduledoc """
  Who may be in a page's room, and what its shared documents are (Issho's
  policy). Notebook is one shared space: every account may join, read
  and write every page, and agents act for the account they work for.

  A page is the room `"page:<id>"`: its text is the document
  `"page:<id>/body"` (Kotoba), its board the room's own document (a
  Hakushi canvas), its table the place `"page:<id>/rows"` (a Masu grid,
  whose rows are in the database).
  """
  @behaviour Issho.Policy

  alias Notebook.Accounts.User
  alias Notebook.{Pages, Repo}

  @impl true
  def authorize(%Issho.Identity{} = identity, "page:" <> id, _action) do
    with {:ok, _user} <- account(identity),
         {page_id, ""} <- Integer.parse(id),
         %Pages.Page{} <- Pages.get(page_id) do
      :ok
    else
      _ -> {:error, :forbidden}
    end
  end

  def authorize(_identity, _room, _action), do: {:error, :forbidden}

  @impl true
  def document(_identity, "page:" <> rest) do
    case String.split(rest, "/") do
      [_id, "body"] -> Kotoba.Issho.document(store: {Notebook.CollabStore, Repo})
      [id] -> board(id)
      _other -> {:error, :not_found}
    end
  end

  def document(_identity, _id), do: {:error, :not_found}

  # A board page's canvas, when an agent opens it before anyone has it
  # open: its saved graph, saved again with each change.
  defp board(id) do
    with {id, ""} <- Integer.parse(id),
         %Pages.Page{kind: "board"} = page <- Pages.get(id) do
      Hakushi.Issho.document(Notebook.Boards.graph(page),
        on_change: Notebook.Boards.on_change(page.id),
        canvas: "board"
      )
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "The page's room."
  def room(%Pages.Page{id: id}), do: "page:#{id}"

  @doc "The page of a room, or a document of it."
  def page_id("page:" <> rest) do
    case Integer.parse(rest) do
      {id, _rest} -> id
      :error -> nil
    end
  end

  def page_id(_other), do: nil

  # A person signs in with an account; an agent works for one.
  defp account(%Issho.Identity{on_behalf_of: %Issho.Identity{} = person}), do: account(person)

  defp account(%Issho.Identity{key: key}) do
    with {id, ""} <- Integer.parse(key),
         %User{} = user <- Repo.get(User, id) do
      {:ok, user}
    else
      _ -> :error
    end
  end
end
