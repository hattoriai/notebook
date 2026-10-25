defmodule Notebook.Repo.Migrations.AddPositions do
  use Ecto.Migration

  import Ecto.Query
  import Narabe.Migration

  # Folders and pages get their place among their siblings, in an order
  # people choose (Narabe): each sibling list starts as the sidebar showed
  # it, the folders by name, then the pages by title.
  def up do
    alter table(:folders) do
      position()
    end

    alter table(:pages) do
      position()
    end

    create index(:folders, [:space_id, :parent_id, :position])
    create index(:pages, [:space_id, :folder_id, :position])

    flush()

    folders = repo().all(from(f in "folders", select: {f.id, f.space_id, f.parent_id, f.name}))

    pages =
      repo().all(from(p in "pages", select: {p.id, p.space_id, p.folder_id, p.title}))

    rows =
      Enum.map(folders, fn {id, space, parent, name} ->
        {{space, parent}, {0, String.downcase(name || "")}, "folders", id}
      end) ++
        Enum.map(pages, fn {id, space, folder, title} ->
          {{space, folder}, {1, String.downcase(title || "")}, "pages", id}
        end)

    for {_siblings, list} <- Enum.group_by(rows, &elem(&1, 0)) do
      list = Enum.sort_by(list, &{elem(&1, 1), elem(&1, 3)})

      for {{_scope, _sort, table, id}, key} <-
            Enum.zip(list, Narabe.Position.between_many(nil, nil, length(list))) do
        repo().update_all(from(r in table, where: r.id == ^id), set: [position: key])
      end
    end
  end

  def down do
    drop index(:pages, [:space_id, :folder_id, :position])
    drop index(:folders, [:space_id, :parent_id, :position])

    alter table(:pages) do
      remove :position
    end

    alter table(:folders) do
      remove :position
    end
  end
end
