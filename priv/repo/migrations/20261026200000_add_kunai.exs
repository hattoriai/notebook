defmodule Notebook.Repo.Migrations.AddKunai do
  use Ecto.Migration

  def up, do: Kunai.Migrations.up(version: 2)
  def down, do: Kunai.Migrations.down(to: 0)
end
