defmodule Notebook.AgentsTest do
  use Notebook.DataCase, async: false

  import Notebook.AccountsFixtures

  alias Notebook.Accounts.Scope
  alias Notebook.Agents
  alias Notebook.Agents.Agent

  setup do
    %{
      hanzo: Scope.for_user(user_fixture(%{name: "Hattori Hanzo"})),
      yuki: Scope.for_user(user_fixture(%{name: "Yuki Hattori"}))
    }
  end

  test "an agent has its own name, key and token, kept as a hash", %{hanzo: hanzo} do
    {:ok, agent, "nbk_" <> _ = token} = Agents.create(hanzo, %{"name" => "  Hanzo's   agent "})
    assert agent.name == "Hanzo's agent"
    assert Agents.key(agent) == "agent:#{agent.id}"
    assert agent.token_hint == String.slice(token, 0, 8)
    refute Repo.get!(Agent, agent.id).token_hash == token
    # 90 days unless told otherwise.
    assert DateTime.diff(agent.expires_at, DateTime.utc_now(), :day) in 89..90

    assert {:ok, %Agent{id: id, user: %{id: user_id}, last_seen_at: %DateTime{}}} =
             Agents.authenticate(token)

    assert id == agent.id and user_id == hanzo.user.id
    assert Agents.authenticate("nbk_not-a-token") == :error
    assert Agents.authenticate("not even ours") == :error

    assert {:error, changeset} = Agents.create(hanzo, %{"name" => " "})
    assert %{name: [_]} = errors_on(changeset)
  end

  test "a token revoked or past its end works no more; only its person revokes it", %{
    hanzo: hanzo,
    yuki: yuki
  } do
    {:ok, agent, token} =
      Agents.create(hanzo, %{"name" => "Hanzo's agent", "lifetime" => "never"})

    assert agent.expires_at == nil

    assert {:error, :not_found} = Agents.revoke(yuki, agent.id)
    assert {:ok, _agent} = Agents.authenticate(token)
    assert {:ok, _agent} = Agents.revoke(hanzo, agent.id)
    assert Agents.authenticate(token) == :error
    assert Agents.list(hanzo) == []
    assert Agents.active() == []

    {:ok, old, old_token} = Agents.create(hanzo, %{"name" => "An old one", "lifetime" => "30"})

    old
    |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(:second), -1, :day))
    |> Repo.update!()

    assert Agents.authenticate(old_token) == :error
    assert Agents.active() == []
  end
end
