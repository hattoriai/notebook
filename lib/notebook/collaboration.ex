defmodule Notebook.Collaboration do
  @moduledoc """
  Who may be in a page's room, and what its shared documents are (Issho's
  policy). A person may do in a page's room what their role in its space
  lets them (`Notebook.Permissions`): a viewer joins and reads, a
  commenter also comments, an editor also writes. An agent may do what
  the person it works for may.

  A page is the room `"page:<id>"`: its text is the document
  `"page:<id>/body"` (Kotoba), its board the room's own document (a
  Hakushi canvas), its table the place `"page:<id>/rows"` (a Masu grid,
  whose rows are in the database).
  """
  @behaviour Issho.Policy

  alias Notebook.Accounts.{Scope, User}
  alias Notebook.{Pages, Permissions, Repo}

  @impl true
  def authorize(%Issho.Identity{} = identity, "page:" <> id, action) do
    with {:ok, user} <- account(identity),
         {page_id, ""} <- Integer.parse(id),
         %Pages.Page{} = page <- Pages.fetch(page_id),
         true <- Permissions.allowed?(Scope.for_user(user), permission(action), page) do
      :ok
    else
      _ -> {:error, :forbidden}
    end
  end

  def authorize(_identity, _room, _action), do: {:error, :forbidden}

  # What each of the room's actions takes on the page.
  defp permission(action) when action in [:join, :read], do: :read
  defp permission(:comment), do: :comment
  defp permission(action) when action in [:write, :lock, :interrupt], do: :edit

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
         %Pages.Page{kind: "board"} = page <- Pages.fetch(id) do
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
