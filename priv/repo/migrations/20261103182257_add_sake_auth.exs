defmodule Notebook.Repo.Migrations.AddSakeAuth do
  use Ecto.Migration

  # The tables of the Notebook's OAuth server for its MCP endpoint, when
  # Notebook settings turn it on (NotebookWeb.MCP.Subject): clients,
  # codes, tokens and consents (Sake.Auth).
  def up, do: Sake.Auth.Migration.up()
  def down, do: Sake.Auth.Migration.down()
end
