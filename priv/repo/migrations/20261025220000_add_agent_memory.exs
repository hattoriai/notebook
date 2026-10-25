defmodule Notebook.Repo.Migrations.AddAgentMemory do
  use Ecto.Migration

  # The agents' memory (Notebook.Memory): files each agent keeps across its
  # sessions, read and written with a bash of its own, and seen and edited
  # by its person; and what its person tells it to be (its instructions,
  # its self.md).
  def change do
    alter table(:agents) do
      add :instructions, :text, null: false, default: ""
    end

    create table(:memory_files) do
      add :agent_id, references(:agents, on_delete: :delete_all), null: false
      # Its path under /memories, "/notes/hanzo.md"; a directory has no content.
      add :path, :string, null: false
      add :content, :text
      add :directory, :boolean, null: false, default: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:memory_files, [:agent_id, :path])
  end
end
