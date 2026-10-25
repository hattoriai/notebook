defmodule Notebook.Repo.Migrations.AddOban do
  use Ecto.Migration

  # Oban's jobs (the notifications' emails and reminders), in SQLite.
  def up, do: Oban.Migration.up()
  def down, do: Oban.Migration.down()
end
