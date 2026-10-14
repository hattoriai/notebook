defmodule Notebook.Repo.Migrations.AddJumonHistory do
  use Ecto.Migration

  # The history of the command palette, see Jumon.History.Ecto.
  def up, do: Jumon.Migration.up(version: 1)
  def down, do: Jumon.Migration.down(version: 1)
end
