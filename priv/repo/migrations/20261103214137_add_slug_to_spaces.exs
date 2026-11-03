defmodule Notebook.Repo.Migrations.AddSlugToSpaces do
  use Ecto.Migration
  import Ecto.Query

  # A space's name in its pages' addresses (hattori.ai/open-source/kotoba),
  # for General and the team spaces; a Private space's pages are under its
  # person's handle. Handles, spaces' slugs and pages' slugs are one list of
  # names. "people" for a space that is not Private means its slug now.
  @reserved ~w(account admin agents api archive assets bots dev favicon.ico feed fonts images inbox issho live
               login logout made-with mcp notebook notifications oauth pages phoenix public robots.txt settings spaces
               up uploads users)

  def up do
    alter table(:spaces) do
      add :slug, :string
    end

    create unique_index(:spaces, [:slug])
    flush()

    repo().update_all(
      from(s in "spaces", where: s.kind != "private" and s.publish_paths == "people"),
      set: [publish_paths: nil]
    )

    taken =
      MapSet.new(
        repo().all(from(u in "users", select: u.handle)) ++
          repo().all(from(p in "pages", where: not is_nil(p.slug), select: p.slug)) ++
          repo().all(from(f in "folders", where: not is_nil(f.slug), select: f.slug)) ++ @reserved
      )

    spaces =
      repo().all(
        from(s in "spaces", where: s.kind != "private", order_by: s.id, select: {s.id, s.name})
      )

    Enum.reduce(spaces, taken, fn {id, name}, taken ->
      base = slugify(name)
      base = if base == "", do: "space", else: base

      slug =
        Stream.iterate(1, &(&1 + 1))
        |> Stream.map(&if(&1 == 1, do: base, else: "#{base}-#{&1}"))
        |> Enum.find(&(not MapSet.member?(taken, &1)))

      repo().update_all(from(s in "spaces", where: s.id == ^id), set: [slug: slug])
      MapSet.put(taken, slug)
    end)
  end

  def down do
    alter table(:spaces) do
      remove :slug
    end
  end

  defp slugify(text) do
    text
    |> to_string()
    |> String.normalize(:nfd)
    |> String.replace(~r/[^A-Za-z0-9\s-]/u, "")
    |> String.downcase()
    |> String.replace(~r/[\s-]+/, "-")
    |> String.trim("-")
    |> String.slice(0, 60)
    |> String.trim("-")
  end
end
