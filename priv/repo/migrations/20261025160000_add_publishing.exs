defmodule Notebook.Repo.Migrations.AddPublishing do
  use Ecto.Migration

  import Ecto.Query

  # Publishing: a person's handle (their pages' paths, /hanzo/kotoba), and
  # a page's or a folder's slug, when it was published and by whom. A
  # folder published is a blog of its published pages. Slugs are one
  # namespace, pages' and folders'. Each person's handle starts as the
  # last word of their name.
  def up do
    alter table(:users) do
      add :handle, :string
    end

    alter table(:pages) do
      add :slug, :string
      add :published_at, :utc_datetime
      add :published_by_id, references(:users, on_delete: :nilify_all)
    end

    alter table(:folders) do
      add :slug, :string
      add :published_at, :utc_datetime
      add :published_by_id, references(:users, on_delete: :nilify_all)
    end

    create unique_index(:users, [:handle])
    create unique_index(:pages, [:slug])
    create unique_index(:folders, [:slug])

    flush()

    taken = MapSet.new()

    repo().all(from(u in "users", select: {u.id, u.name}, order_by: u.id))
    |> Enum.reduce(taken, fn {id, name}, taken ->
      base = (name || "") |> String.split() |> List.last() |> Kernel.||("person") |> slug()

      handle =
        Stream.iterate(1, &(&1 + 1))
        |> Stream.map(&if(&1 == 1, do: base, else: "#{base}-#{&1}"))
        |> Enum.find(&(&1 not in taken))

      repo().update_all(from(u in "users", where: u.id == ^id), set: [handle: handle])
      MapSet.put(taken, handle)
    end)
  end

  def down do
    drop index(:folders, [:slug])
    drop index(:pages, [:slug])
    drop index(:users, [:handle])

    alter table(:folders) do
      remove :published_by_id
      remove :published_at
      remove :slug
    end

    alter table(:pages) do
      remove :published_by_id
      remove :published_at
      remove :slug
    end

    alter table(:users) do
      remove :handle
    end
  end

  defp slug(text) do
    text
    |> String.normalize(:nfd)
    |> String.replace(~r/[^A-Za-z0-9\s-]/u, "")
    |> String.downcase()
    |> String.replace(~r/[\s-]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "person"
      slug -> slug
    end
  end
end
