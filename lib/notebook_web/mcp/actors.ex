defmodule NotebookWeb.MCP.Actors do
  @moduledoc """
  Who an MCP call acts as (`Sake.Actors`), each call on its own: the
  model calls `list_actors`, takes on one with `act_as`, and passes its id
  as `as` to the tools.

    * A client with an agent's token is that agent, and only it.
    * A client with OAuth (Notebook settings) acts for the person who
      signed in: as any of their agents (the Agents page), and, for an
      admin, as any of the notebook's bots that is on. A call without
      `as` acts as their newest agent.

  An actor's instructions are its persona: an agent's `self.md`, which its
  person writes on the Agents page, or a bot's instructions. Every `as` is
  checked against the person on every call (`fetch/2`).
  """
  @behaviour Sake.Actors

  import Ecto.Query

  alias Notebook.Accounts.{Scope, User}
  alias Notebook.Agents.Agent
  alias Notebook.Bots.Bot
  alias Notebook.{Agents, Bots, Repo}
  alias Sake.Actors.Actor

  @impl true
  def list(%{scope: %Agent{} = agent}), do: [actor(agent)]

  def list(%{scope: %User{} = user}) do
    scope = Scope.for_user(user)
    agents = scope |> Agents.list() |> Enum.map(&actor(%{&1 | user: user}))
    bots = for %Bot{enabled: true} = bot <- Bots.list(scope), do: actor(bot)
    agents ++ bots
  end

  def list(_ctx), do: []

  @impl true
  def fetch(%{scope: %Agent{} = agent}, id),
    do: if(id == Agents.key(agent), do: {:ok, actor(agent)}, else: :error)

  def fetch(%{scope: %User{} = user}, "agent:" <> id) do
    with {id, ""} <- Integer.parse(id),
         %Agent{} = agent <-
           Repo.one(
             from a in Agent,
               where: a.id == ^id and a.user_id == ^user.id and is_nil(a.revoked_at)
           ) do
      {:ok, actor(%{agent | user: user})}
    else
      _ -> :error
    end
  end

  def fetch(%{scope: %User{} = user}, "bot:" <> _ = key) do
    with true <- Scope.admin?(Scope.for_user(user)),
         %Bot{enabled: true} = bot <- Bots.by_key(key) do
      {:ok, actor(bot)}
    else
      _ -> :error
    end
  end

  def fetch(_ctx, _id), do: :error

  @impl true
  def default(%{scope: %Agent{} = agent}), do: actor(agent)

  def default(%{scope: %User{} = user}) do
    case Agents.list(Scope.for_user(user)) do
      [agent | _] -> actor(%{agent | user: user})
      [] -> nil
    end
  end

  def default(_ctx), do: nil

  defp actor(%Agent{} = agent) do
    %Actor{
      id: Agents.key(agent),
      name: agent.name,
      description: "Your agent",
      instructions: persona(agent.instructions),
      data: agent
    }
  end

  defp actor(%Bot{} = bot) do
    %Actor{
      id: Bots.key(bot),
      name: bot.name,
      description: "The notebook's bot",
      instructions: persona(bot.instructions),
      data: bot
    }
  end

  defp persona(text) when is_binary(text), do: if(String.trim(text) == "", do: nil, else: text)
  defp persona(_text), do: nil
end
