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
  page. A visitor of a published page may ask a bot that answers visitors
  there.

  A bot of the notebook (`Notebook.Bots`, `"bot:<id>"`) may do what its
  account's roles let it, as an agent: never on what is off limits to
  agents. An agent or a bot may hand a task to a bot that takes them, or
  to a person's agent, that may read the room (`Issho.Handoffs`).

  A page is the room `"page:<id>"`: its text is the document
  `"page:<id>/body"` (Kotoba), its board the room's own document (a
  Hakushi canvas), its table the place `"page:<id>/rows"` (a Masu grid,
  whose rows are in the database).
  """
  @behaviour Issho.Policy

  alias Notebook.Accounts.{Scope, User}
  alias Notebook.{Pages, Permissions, Repo}

  @impl true
  # A visitor reads a published page's room, and does nothing else there.
  def authorize(%Issho.Identity{kind: :guest}, "page:" <> id, action) do
    with :read <- action,
         {page_id, ""} <- Integer.parse(id),
         %Pages.Page{} = page <- Pages.fetch(page_id),
         true <- Notebook.Publishing.published?(page) do
      :ok
    else
      _ -> {:error, :forbidden}
    end
  end

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

  # A visitor asks a bot that answers visitors, on a published page it reads.
  def ask(%Issho.Identity{kind: :guest}, "page:" <> id = room, "bot:" <> _ = bot) do
    with {page_id, ""} <- Integer.parse(id),
         %Pages.Page{} = page <- Pages.fetch(page_id),
         true <- Notebook.Publishing.published?(page),
         %Notebook.Bots.Bot{} = bot <- Notebook.Bots.by_key(bot),
         true <- bot in Notebook.Bots.public_for(page) || :not_public,
         :ok <- authorize(Issho.Identity.new(Notebook.Bots.actor(bot)), room, :read) do
      :ok
    else
      _ -> {:error, :forbidden}
    end
  end

  def ask(_identity, _room, _agent), do: {:error, :forbidden}

  @doc false
  # An agent or a bot hands a task to a bot that takes them (mentions and
  # tasks wake it the same way), or to a person's agent, when the one it
  # goes to may read the room.
  @impl true
  def hand_off(%Issho.Identity{kind: kind}, room, to) when kind in [:agent, :service] do
    case target(to) do
      nil -> {:error, :forbidden}
      identity -> authorize(identity, room, :read)
    end
  end

  def hand_off(_identity, _room, _to), do: {:error, :forbidden}

  defp target("bot:" <> _ = key) do
    case Notebook.Bots.by_key(key) do
      %Notebook.Bots.Bot{enabled: true, on_mention: true} = bot ->
        Issho.Identity.new(Notebook.Bots.actor(bot))

      _ ->
        nil
    end
  end

  defp target("agent:" <> id) do
    with {agent_id, ""} <- Integer.parse(id),
         %Notebook.Agents.Agent{revoked_at: nil} = agent <-
           Repo.get(Notebook.Agents.Agent, agent_id) |> Repo.preload(:user) do
      Issho.Identity.new(%{id: Notebook.Agents.key(agent), name: agent.name, kind: :agent},
        on_behalf_of: %{id: to_string(agent.user.id), name: agent.user.name}
      )
    else
      _ -> nil
    end
  end

  defp target(_key), do: nil

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

  # A bot asks as its account's agent: not on what is off limits to agents.
  defp scope(user, %Issho.Identity{key: "bot:" <> _ = key}), do: Scope.for_agent(user, key)

  defp scope(user, %Issho.Identity{claims: claims}),
    do: user |> Scope.for_user() |> Scope.with_links(claims[:links] || claims["links"] || [])

  # A person signs in with an account; an agent works for one.
  defp account(%Issho.Identity{on_behalf_of: %Issho.Identity{} = person}), do: account(person)

  # A bot works with its account's rights, while it is on.
  defp account(%Issho.Identity{key: "bot:" <> _ = key}) do
    case Notebook.Bots.by_key(key) do
      %Notebook.Bots.Bot{enabled: true, user: %User{} = user} -> {:ok, user}
      _ -> :error
    end
  end

  defp account(%Issho.Identity{key: key}) do
    with {id, ""} <- Integer.parse(key),
         %User{} = user <- Repo.get(User, id) do
      {:ok, user}
    else
      _ -> :error
    end
  end
end
