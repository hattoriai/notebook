defmodule Notebook.Collaboration do
  @moduledoc """
  Who may be in a page's room, and what its shared documents are (Issho's
  policy). A person may do in a page's room what their role in its space
  lets them (`Notebook.Permissions`), or a share of the page (with them,
  or a link they followed): a viewer joins and reads, a commenter also
  comments, an editor also writes. An agent may do what
  the person it works for may, but not on a page off limits to agents.

  A person may ask one of their own agents about what they selected
  (`Issho.Requests`): an agent of theirs, not revoked, that may read the
  page.

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
         true <- Permissions.allowed?(scope(user, identity), permission(action), page) do
      :ok
    else
      _ -> {:error, :forbidden}
    end
  end

  def authorize(_identity, _room, _action), do: {:error, :forbidden}

  @impl true
  def ask(%Issho.Identity{on_behalf_of: nil} = identity, "page:" <> _ = room, "agent:" <> id) do
    with {:ok, user} <- account(identity),
         {agent_id, ""} <- Integer.parse(id),
         %Notebook.Agents.Agent{revoked_at: nil} = agent <-
           Repo.get_by(Notebook.Agents.Agent, id: agent_id, user_id: user.id),
         agent_identity =
           Issho.Identity.new(%{id: Notebook.Agents.key(agent), name: agent.name, kind: :agent},
             on_behalf_of: identity
           ),
         :ok <- authorize(agent_identity, room, :read) do
      :ok
    else
      _ -> {:error, :forbidden}
    end
  end

  def ask(_identity, _room, _agent), do: {:error, :forbidden}

  # What each of the room's actions takes on the page.
  defp permission(action) when action in [:join, :read], do: :read
  defp permission(:comment), do: :comment
  defp permission(action) when action in [:write, :lock, :interrupt], do: :edit

  @impl true
  def document(_identity, "page:" <> rest) do
    case String.split(rest, "/") do
      [_id, "body"] -> Kotoba.Issho.document(store: {Notebook.CollabStore, Repo})
      [_id, "chart:" <> chart_id] -> Notebook.Charts.shared(chart_id)
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

  @doc """
  The scope of whoever an identity of the rooms is: a person, with the
  links they followed, or an agent as its person's agent. For the
  Notebook's actions (`Notebook.Actions`), run as their `by`.
  """
  def scope_of(%Issho.Identity{} = identity) do
    with {:ok, user} <- account(identity), do: {:ok, scope(user, identity)}
  end

  # The person's scope, with the links they followed (`Notebook.Sharing`),
  # which their identity carries, signed, from the page they joined from.
  # An agent (on behalf of its person) asks as their agent: not on what is
  # off limits to agents.
  defp scope(user, %Issho.Identity{on_behalf_of: %Issho.Identity{}, key: key}),
    do: Scope.for_agent(user, key)

  defp scope(user, %Issho.Identity{claims: claims}),
    do: user |> Scope.for_user() |> Scope.with_links(claims[:links] || claims["links"] || [])

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
