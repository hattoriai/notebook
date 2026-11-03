defmodule Notebook.Repo.Migrations.AddSlugsToAllPages do
  use Ecto.Migration
  import Ecto.Query

  # Every page has a slug now, from its title: its address in the notebook
  # (/pages/kotoba), the same word it is published under. One list of names
  # with handles, spaces' and folders' slugs (Notebook.Publishing).
  @reserved ~w(account admin agents api archive assets bots dev favicon.ico feed fonts images inbox issho live
               login logout made-with mcp notebook notifications oauth pages phoenix public robots.txt settings spaces
               up uploads users)

  def up do
    taken =
      MapSet.new(
        repo().all(from(u in "users", select: u.handle)) ++
          repo().all(from(s in "spaces", where: not is_nil(s.slug), select: s.slug)) ++
          repo().all(from(f in "folders", where: not is_nil(f.slug), select: f.slug)) ++
          repo().all(from(p in "pages", where: not is_nil(p.slug), select: p.slug)) ++ @reserved
      )

    pages =
      repo().all(
        from(p in "pages", where: is_nil(p.slug), order_by: p.id, select: {p.id, p.title})
      )

    Enum.reduce(pages, taken, fn {id, title}, taken ->
      base = slugify(title)
      base = if base == "", do: "page", else: base

      slug =
        Stream.iterate(1, &(&1 + 1))
        |> Stream.map(&if(&1 == 1, do: base, else: "#{base}-#{&1}"))
        |> Enum.find(&(not MapSet.member?(taken, &1)))

      repo().update_all(from(p in "pages", where: p.id == ^id), set: [slug: slug])
      MapSet.put(taken, slug)
    end)
  end

  def down, do: :ok

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
