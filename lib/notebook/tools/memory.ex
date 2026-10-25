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
    and may change them. No network; a file holds at most 64 KB.
    """,
    annotations: []

  arg(:command, :string, required: true, max_length: 4_000, description: "A bash command line")

  @impl true
  def call(%{command: command}, ctx) do
    case agent_id(ctx) do
      nil ->
        {:error, "Only an agent has a memory: connect as one (see the Notebook's Agents page)."}

      id ->
        {:ok, Notebook.Memory.Shell.run(id, command)}
    end
  end

  # The agent's own key in the rooms: "agent:<id>" (Notebook.Agents.key/1).
  defp agent_id(ctx) do
    with "agent:" <> rest <- Issho.Identity.new(ctx.actor).key,
         {id, ""} <- Integer.parse(rest),
         %Notebook.Agents.Agent{revoked_at: nil} <- Notebook.Repo.get(Notebook.Agents.Agent, id) do
      id
    else
      _ -> nil
    end
  end
end
