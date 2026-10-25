defmodule Notebook.Tools.Memory do
  @moduledoc false
  use Issho.Tool,
    name: "memory",
    description: """
    Your memory: files of your own under /memories, which last between your
    sessions, kept in the Notebook. Run a bash command there (each command
    starts in /memories, in a fresh shell): ls, cat, grep -rn, find, tree,
    head, wc, sed -i, echo >> file, printf > file, mkdir -p, mv, rm.
    Start each session with `cat self.md`, what the person you work for
    tells you to be (theirs to write; you may not change it), then `tree`,
    and read what bears on the work. Write down what you should not have to
    be told twice: their preferences, the notebook's conventions, what you
    learned about a page or a person, as short Markdown notes in files you
    name and keep tidy (people/hanzo.md, pages/the-forge.md). Correct a note
    when it no longer holds rather than adding another. They see these files
    and may change them. A note keeps the pages you were on as you wrote it;
    learned on a page you may no longer read, it is not there for you. No
    network; a file holds at most 64 KB.
    """,
    annotations: []

  arg(:command, :string, required: true, max_length: 4_000, description: "A bash command line")

  @impl true
  def call(%{command: command}, ctx) do
    case agent(ctx) do
      nil ->
        {:error, "Only an agent has a memory: connect as one (see the Notebook's Agents page)."}

      agent ->
        # It sees what it may read as its person's agent, and notes keep
        # the pages it is on.
        scope = Notebook.Accounts.Scope.for_agent(agent.user, Notebook.Agents.key(agent))
        {:ok, Notebook.Memory.Shell.run(agent.id, command, scope: scope, sources: sources(agent))}
    end
  end

  # The agent of the caller's own key in the rooms: "agent:<id>" (Notebook.Agents.key/1).
  defp agent(ctx) do
    with "agent:" <> rest <- Issho.Identity.new(ctx.actor).key,
         {id, ""} <- Integer.parse(rest),
         %Notebook.Agents.Agent{revoked_at: nil} = agent <-
           Notebook.Repo.get(Notebook.Agents.Agent, id) do
      Notebook.Repo.preload(agent, :user)
    else
      _ -> nil
    end
  end

  # Where it learns what it notes now: the pages whose rooms it is in.
  defp sources(agent) do
    Notebook.Issho
    |> Issho.Agents.rooms(Notebook.Agents.key(agent))
    |> Enum.map(&Notebook.Collaboration.page_id/1)
    |> Enum.reject(&is_nil/1)
  end
end
