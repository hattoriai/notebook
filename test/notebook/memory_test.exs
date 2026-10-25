defmodule Notebook.MemoryTest do
  use Notebook.DataCase, async: false

  import Notebook.AccountsFixtures

  alias Notebook.Accounts.Scope
  alias Notebook.{Agents, Memory}
  alias Notebook.Memory.Shell

  setup do
    scope = Scope.for_user(user_fixture(%{name: "Hattori Hanzo"}))
    {:ok, agent, _token} = Agents.create(scope, %{"name" => "Hanzo's apprentice"})
    {:ok, other, _token} = Agents.create(scope, %{"name" => "Another"})
    %{agent: agent, other: other}
  end

  defp sh(agent, command), do: Shell.run(agent.id, command)

  test "an agent's memory is files a bash reads and writes, kept in the database", %{
    agent: agent,
    other: other
  } do
    assert %{"exit_code" => 0} =
             sh(
               agent,
               "mkdir -p people && echo '- summaries in bold' > people/hanzo.md && echo '- Masamune forges' >> people/hanzo.md"
             )

    # A new shell, the same memory: nothing is kept in a process.
    assert %{"stdout" => "- summaries in bold\n- Masamune forges\n"} =
             sh(agent, "cat people/hanzo.md")

    assert %{"stdout" => "./people/hanzo.md:2:- Masamune forges\n"} =
             sh(agent, "grep -rn Masamune .")

    assert %{"exit_code" => 0} =
             sh(agent, "sed -i 's/in bold/in bold, at the top/' people/hanzo.md")

    assert %{content: "- summaries in bold, at the top\n- Masamune forges\n"} =
             Memory.get(agent.id, "/people/hanzo.md")

    assert %{"stdout" => "./people/hanzo.md\n./self.md\n"} = sh(agent, "find . -type f | sort")

    assert %{"exit_code" => 0} =
             sh(agent, "mv people/hanzo.md people/master.md && rm -r people && ls")

    assert Memory.get(agent.id, "/people/master.md") == nil

    # Each agent its own.
    assert %{"exit_code" => 0} = sh(other, "echo mine > mine.md")
    assert %{"exit_code" => 1} = sh(agent, "cat mine.md")
  end

  test "self.md is what its person tells it to be: the agent reads it and may not change it", %{
    agent: agent
  } do
    {:ok, _agent} = Memory.put_instructions(agent, "Speak plainly. Never touch the Journal.")
    assert %{"stdout" => "Speak plainly. Never touch the Journal."} = sh(agent, "cat self.md")
    assert %{"exit_code" => 1, "stderr" => stderr} = sh(agent, "echo hacked > self.md")
    assert stderr =~ "Permission denied"
    assert %{"exit_code" => 1} = sh(agent, "rm self.md")
    assert %{"stdout" => "Speak plainly. Never touch the Journal."} = sh(agent, "cat self.md")
  end

  test "a bash with nothing but its memory: no host files, no network, bounded", %{agent: agent} do
    assert %{"exit_code" => 1} = sh(agent, "cat /etc/passwd")
    assert %{"stderr" => stderr} = sh(agent, "curl https://example.com")
    assert stderr =~ "network access is disabled"
    # Bounded: just_bash stops a loop that would not end, and says so.
    assert %{"stderr" => "loop: iteration limit exceeded\n"} = sh(agent, "while true; do :; done")

    big = String.duplicate("x", Memory.limits().file + 1)
    assert {:error, :efbig} = Memory.write(agent.id, "/big.md", big)
    assert {:error, :eacces} = Memory.write(agent.id, "/self.md", "no")
    assert {:ok, _} = Memory.write(agent.id, "/a.md", "x")
    assert {:error, :enotdir} = Memory.write(agent.id, "/a.md/b.md", "x")
  end

  test "paths are exact: a directory's files only, whatever their case", %{agent: agent} do
    {:ok, _} = Memory.write(agent.id, "/notes/a.md", "a")
    {:ok, _} = Memory.write(agent.id, "/Notes/b.md", "b")
    {:ok, _} = Memory.write(agent.id, "/notes_old/c.md", "c")
    assert %{"stdout" => "a.md\n"} = sh(agent, "ls notes")
    assert {:ok, _} = Memory.rm(agent.id, "/notes", recursive: true)
    assert Memory.get(agent.id, "/Notes/b.md")
    assert Memory.get(agent.id, "/notes_old/c.md")
  end

  test "the memory tool is an agent's own, by its key", %{agent: agent} do
    ctx =
      Issho.Tool.Context.new(Notebook.Issho, %{
        id: Agents.key(agent),
        name: agent.name,
        kind: :agent
      })

    assert {:ok, %{"exit_code" => 0}} =
             Notebook.Tools.Memory.call(%{command: "echo hi > hi.md"}, ctx)

    assert Memory.get(agent.id, "/hi.md").content == "hi\n"

    person = Issho.Tool.Context.new(Notebook.Issho, %{id: "1", name: "Hanzo"})
    assert {:error, _} = Notebook.Tools.Memory.call(%{command: "ls"}, person)

    {:ok, _} =
      Agents.revoke(
        Scope.for_user(Notebook.Repo.get!(Notebook.Accounts.User, agent.user_id)),
        agent.id
      )

    assert {:error, _} = Notebook.Tools.Memory.call(%{command: "ls"}, ctx)
  end
end
