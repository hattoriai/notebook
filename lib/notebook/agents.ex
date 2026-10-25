defmodule Notebook.Agents do
  @moduledoc """
  The agents people connect, each with its own identity: a name everyone
  sees in the pages ("Hanzo's agent"), the person it works for, and its
  own token, which can expire and be revoked. In a page's room an agent
  is an Issho actor of its own (`key/1`), acting on behalf of its person:
  the room's policy, the tools and the pages' functions treat it as they
  treat that person, and people see, mention and pause it by its name.

  A token is shown once, when the agent is made; the Notebook keeps only
  its hash.
  """
  import Ecto.Query

  alias Notebook.Accounts.{Scope, User}
  alias Notebook.Agents.Agent
  alias Notebook.Repo

  @prefix "nbk_"
  @lifetimes %{"30" => 30, "90" => 90, "365" => 365, "never" => nil}

  @doc "How long a token may last, as the form offers it: days, or `\"never\"`."
  def lifetimes,
    do: [{"30 days", "30"}, {"90 days", "90"}, {"A year", "365"}, {"No end", "never"}]

  @doc "An agent's key in every room: its own, not its person's."
  def key(%Agent{id: id}), do: "agent:#{id}"

  @doc "A new agent, for the form."
  def change(attrs \\ %{}), do: Agent.changeset(%Agent{}, attrs)

  @doc """
  Connects an agent for the scope's person: `{:ok, agent, token}`, the
  token to give the agent's client, shown this once. `"lifetime"` is
  days (`lifetimes/0`), 90 unless given.
  """
  def create(%Scope{user: %User{} = user}, attrs) do
    token = @prefix <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    days = Map.get(@lifetimes, attrs["lifetime"] || attrs[:lifetime] || "90", 90)
    expires_at = days && DateTime.utc_now(:second) |> DateTime.add(days, :day)

    %Agent{
      user_id: user.id,
      token_hash: hash(token),
      token_hint: String.slice(token, 0, 8),
      expires_at: expires_at
    }
    |> Agent.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, agent} -> {:ok, %{agent | user: user}, token}
      error -> error
    end
  end

  @doc "The scope's person's agents not revoked, the newest first."
  def list(%Scope{user: %User{id: id}}) do
    Agent
    |> where([a], a.user_id == ^id and is_nil(a.revoked_at))
    |> order_by(desc: :inserted_at, desc: :id)
    |> Repo.all()
  end

  @doc "Every agent that may still work, with its person: whom comments may mention."
  def active do
    now = DateTime.utc_now(:second)

    Agent
    |> where([a], is_nil(a.revoked_at) and (is_nil(a.expires_at) or a.expires_at > ^now))
    |> order_by(:name)
    |> preload(:user)
    |> Repo.all()
  end

  @doc "Revokes one of the scope's person's agents: its token works no more."
  def revoke(%Scope{user: %User{id: id}}, agent_id) do
    case Repo.get_by(Agent, id: agent_id, user_id: id) do
      %Agent{revoked_at: nil} = agent ->
        agent |> Ecto.Changeset.change(revoked_at: DateTime.utc_now(:second)) |> Repo.update()

      _missing_or_revoked ->
        {:error, :not_found}
    end
  end

  @doc """
  The agent whose token this is, with its person, if it may still work
  (not revoked, not expired); its last visit noted, at most once a minute.
  """
  def authenticate(@prefix <> _ = token) do
    now = DateTime.utc_now(:second)

    with %Agent{revoked_at: nil} = agent <- Repo.get_by(Agent, token_hash: hash(token)),
         true <- is_nil(agent.expires_at) or DateTime.after?(agent.expires_at, now) do
      {:ok, agent |> seen(now) |> Repo.preload(:user)}
    else
      _ -> :error
    end
  end

  def authenticate(_token), do: :error

  defp seen(%Agent{last_seen_at: at} = agent, now) do
    if is_nil(at) or DateTime.diff(now, at) >= 60 do
      {:ok, agent} = agent |> Ecto.Changeset.change(last_seen_at: now) |> Repo.update()
      agent
    else
      agent
    end
  end

  defp hash(token), do: :crypto.hash(:sha256, token)
end
