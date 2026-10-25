defmodule Notebook.Search do
  @moduledoc """
  The notebook's words, searched (SQLite's FTS5, `pages_fts`): each page's
  title, its text, and its records (a table page's rows, a database
  page's records), without case or accents, each word as the start of a
  word ("forg" finds "forge"). The pages the scope may read, the best
  first: a word in a title weighs most, then in the text, then in the
  records. Each found page comes with the words around what matched.
  """
  import Ecto.Query

  alias Notebook.Pages.Page
  alias Notebook.{Permissions, Repo}

  @doc """
  The pages that have every word of the query, that the scope may read,
  the best first, each with a snippet: `[%{page: page, snippet: parts}]`,
  whose parts are `{text, matched?}`. Options: `:limit` (20), `:archived`
  (false).
  """
  def search(scope, query, opts \\ []) do
    case match(query) do
      nil ->
        []

      match ->
        found =
          from(
            f in fragment(
              "SELECT rowid AS id, bm25(pages_fts, 10.0, 1.0, 0.5) AS rank, snippet(pages_fts, -1, char(2), char(3), '…', 14) AS snippet FROM pages_fts WHERE pages_fts MATCH ?",
              ^match
            ),
            select: %{id: f.id, rank: f.rank, snippet: f.snippet}
          )

        from(p in Page,
          join: f in subquery(found),
          on: f.id == p.id,
          order_by: [asc: f.rank],
          limit: ^Keyword.get(opts, :limit, 20),
          preload: [:author, :space],
          select: {p, f.snippet}
        )
        |> archived(Keyword.get(opts, :archived, false))
        |> Permissions.where_allowed(scope, :read)
        |> Repo.all()
        |> Enum.map(fn {page, snippet} -> %{page: page, snippet: parts(snippet)} end)
    end
  end

  @doc """
  A query as FTS5 reads it: each word, quoted (so that no word is an
  operator), as the start of a word. Nil when it has no words.
  """
  def match(query) do
    case Regex.scan(~r/[\p{L}\p{N}]+/u, to_string(query)) do
      [] -> nil
      words -> Enum.map_join(words, " ", fn [word] -> ~s("#{word}"*) end)
    end
  end

  defp archived(query, true), do: where(query, [p], not is_nil(p.archived_at))
  defp archived(query, false), do: where(query, [p], is_nil(p.archived_at))

  # A snippet's parts: what matched, marked by the characters 2 and 3.
  defp parts(nil), do: []

  defp parts(snippet) do
    snippet
    |> String.replace(~r/\s+/u, " ")
    |> String.split(<<2>>)
    |> Enum.with_index()
    |> Enum.flat_map(fn
      {text, 0} ->
        [{text, false}]

      {text, _i} ->
        case String.split(text, <<3>>, parts: 2) do
          [matched, rest] -> [{matched, true}, {rest, false}]
          [rest] -> [{rest, false}]
        end
    end)
    |> Enum.reject(fn {text, _matched?} -> text == "" end)
  end
end
