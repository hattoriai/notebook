defmodule Notebook.Repo.Migrations.AddCardbox do
  use Ecto.Migration

  # The tables of database pages (Cardbox): collections, their fields,
  # records, links and saved views.
  def up, do: Cardbox.Migrations.up(version: 1)
  def down, do: Cardbox.Migrations.down(to: 0)
end
