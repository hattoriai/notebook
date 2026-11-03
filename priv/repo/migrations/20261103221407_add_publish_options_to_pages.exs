defmodule Notebook.Repo.Migrations.AddPublishOptionsToPages do
  use Ecto.Migration

  # How a published page reads: whether it shows its author and its date,
  # and what search engines and link previews say of it.
  def change do
    alter table(:pages) do
      add :publish_options, :map, null: false, default: %{}
    end
  end
end
