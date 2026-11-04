defmodule Notebook.Repo.Migrations.AddIconToPages do
  use Ecto.Migration

  # A page's own icon, as a space's: one of the notebook's icons, an emoji,
  # or an uploaded image ("image:<url>"); none, its kind's.
  def change do
    alter table(:pages) do
      add :icon, :string
    end
  end
end
