defmodule Notebook.Repo.Migrations.AddMemorySources do
  use Ecto.Migration

  # Where an agent learned what it noted: the pages whose rooms it was in
  # when it wrote the file. A note learned on a page the agent may no
  # longer read is not there for it (Notebook.Memory).
  def change do
    alter table(:memory_files) do
      add :sources, :text, null: false, default: "[]"
    end
  end
end
