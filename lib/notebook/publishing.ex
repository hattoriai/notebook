defmodule Notebook.Publishing do
  @moduledoc """
  Pages anyone may read, at paths of the notebook's own. A page's editors
  publish it, under a slug; a folder published is a blog of its published
  pages, with an RSS feed.

  The paths are by person, `/hanzo/kotoba` (a team's notebook), or the
  notebook's alone, `/kotoba` (one person's); never with an `@`. They may
  sit under a prefix, and be read at another address: a site's own, whose
  proxy (a Cloudflare Worker) sends the prefix to the notebook.

      config :notebook, :publishing,
        url: "https://hattori.ai",   # where readers read (the notebook's own by default)
        prefix: "/libs",             # what the proxy sends to the notebook ("" by default)
        paths: :people,              # /hanzo/kotoba, or :solo for /kotoba
        name: "Hattori"              # the site's name, in the pages and the feeds

  A public page's HTML goes through the proxy; its styles, scripts, files
  and live socket come from the notebook's own address, which accepts the
  publishing address as an origin (`origin?/1`).
  """
  import Ecto.Query

  alias Notebook.Accounts.{Scope, User}
  alias Notebook.Pages.Page
  alias Notebook.Spaces.Folder
  alias Notebook.{Pages, Repo, Spaces}

  # The first words of the notebook's own paths: no handle or slug at the
  # top takes them.
  @reserved ~w(admin agents api archive assets dev favicon.ico feed fonts images inbox issho live
               login logout mcp notifications pages phoenix public robots.txt settings spaces uploads users)

  @doc "The words no handle or slug takes: the notebook's own paths."
  def reserved, do: @reserved

  @doc "The publishing config, with its defaults."
  def config do
    config = Application.get_env(:notebook, :publishing, [])

    %{
      url: config[:url] || NotebookWeb.Endpoint.url(),
      prefix: config[:prefix] |> to_string() |> String.trim_trailing("/"),
      paths: if(config[:paths] == :solo, do: :solo, else: :people),
      name: config[:name] || "Notebook"
    }
  end

  ## Slugs and handles

  @doc "Words as a slug: lowercase letters, digits and dashes."
  def slugify(text) do
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

  @doc "A handle for a new person, from their name: its last word, made free."
  def free_handle(name) do
    base = name |> to_string() |> String.split() |> List.last() |> slugify()
    base = if String.length(base) < 2 or base in @reserved, do: "person", else: base
    free(base, fn handle -> Repo.exists?(from u in User, where: u.handle == ^handle) end)
  end

  defp free(base, taken?) do
    Stream.iterate(1, &(&1 + 1))
    |> Stream.map(&if(&1 == 1, do: base, else: "#{base}-#{&1}"))
    |> Enum.find(&(not taken?.(&1)))
  end

  # A slug no other page or folder has.
  defp slug_taken?(slug, %{__struct__: schema, id: id}) do
    Repo.exists?(from p in Page, where: p.slug == ^slug and (^(schema != Page) or p.id != ^id)) or
      Repo.exists?(
        from f in Folder, where: f.slug == ^slug and (^(schema != Folder) or f.id != ^id)
      )
  end

  defp check_slug(slug, resource) do
    cond do
      not Regex.match?(~r/^[a-z0-9][a-z0-9-]{0,59}$/, slug) ->
        {:error, "A slug is lowercase letters, digits and dashes."}

      slug in @reserved ->
        {:error, "“#{slug}” is a path of the notebook: choose another."}

      slug_taken?(slug, resource) ->
        {:error, "Another page or folder is published as “#{slug}”."}

      true ->
        :ok
    end
  end

  @doc "A slug free for it, from its title or name."
  def suggest_slug(%{slug: slug}) when is_binary(slug), do: slug

  def suggest_slug(resource) do
    base = resource |> title() |> slugify()
    base = if base == "" or base in @reserved, do: "page", else: base
    free(base, &slug_taken?(&1, resource))
  end

  defp title(%Page{title: title}), do: title
  defp title(%Folder{name: name}), do: name

  ## Publishing

  @doc """
  Publishes a page, or a folder as a blog, under a slug (its last one, or
  one from its title): its editors may. Published again, it keeps the
  time it was first published.
  """
  def publish(%Scope{user: user} = scope, resource, slug \\ nil) do
    slug = (slug && String.trim(slug)) || suggest_slug(resource)

    with :ok <- authorize(scope, resource),
         :ok <- check_slug(slug, resource) do
      resource
      |> Ecto.Changeset.change(
        slug: slug,
        published_at: resource.published_at || DateTime.utc_now(:second),
        published_by_id: user.id
      )
      |> Ecto.Changeset.unique_constraint(:slug)
      |> Repo.update()
      |> tap(fn _ -> Spaces.tree_changed() end)
    end
  end

  @doc "Takes it back: no one reads it at its path. It keeps its slug for the next time."
  def unpublish(%Scope{} = scope, resource) do
    with :ok <- authorize(scope, resource) do
      resource
      |> Ecto.Changeset.change(published_at: nil)
      |> Repo.update()
      |> tap(fn _ -> Spaces.tree_changed() end)
    end
  end

  defp authorize(scope, %Page{} = page), do: Pages.authorize(scope, :edit, page)

  defp authorize(scope, %Folder{} = folder),
    do: Notebook.Permissions.authorize(scope, :edit, folder)

  @doc "Whether the scope may publish it: its editors may."
  def can_publish?(scope, resource), do: authorize(scope, resource) == :ok

  @doc "Whether it is published."
  def published?(%{published_at: at}), do: not is_nil(at)

  ## Paths

  @doc """
  Its path, as readers read it: the prefix, the publisher's handle (by
  person), its blog's slug (a page in a published folder), its slug.
  """
  def path(resource) do
    resource = Repo.preload(resource, [:published_by, folder_of(resource)], force: true)
    %{prefix: prefix, paths: paths} = config()

    words =
      [paths == :people && resource.published_by && resource.published_by.handle] ++
        blog_words(resource) ++ [resource.slug]

    prefix <> "/" <> Enum.join(Enum.filter(words, & &1), "/")
  end

  defp folder_of(%Page{}), do: :folder
  defp folder_of(%Folder{}), do: :parent

  defp blog_words(%Page{folder: %Folder{published_at: %DateTime{}, slug: slug}}), do: [slug]
  defp blog_words(_resource), do: []

  @doc "Its address, where readers read it."
  def url(resource), do: config().url <> path(resource)

  @doc "Its blog's feed's address."
  def feed_url(%Folder{} = folder), do: url(folder) <> "/feed.xml"

  @doc """
  What a request's path is: a page, a blog with its posts, a blog's feed,
  a person's index (their handle, by person), or a redirect to its path
  (an old handle, a page moved out of its blog), else `:not_found`. The path's words, the prefix's among them or
  not.
  """
  def resolve(words) when is_list(words) do
    words = strip_prefix(words)

    {words, feed?} =
      if List.last(words) == "feed.xml", do: {Enum.drop(words, -1), true}, else: {words, false}

    with [_ | _] <- words,
         :page <- person(words, feed?),
         slug = List.last(words),
         {kind, resource} <- find(slug) do
      canonical = path(resource)

      cond do
        feed? and kind == :blog -> {:feed, resource, posts(resource)}
        feed? -> :not_found
        canonical != config().prefix <> "/" <> Enum.join(words, "/") -> {:redirect, canonical}
        kind == :blog -> {:blog, resource, posts(resource)}
        true -> {:page, resource}
      end
    else
      {:person, _user, _published} = person -> person
      _ -> :not_found
    end
  end

  # A person's handle alone, by person: their published pages and blogs.
  defp person([handle], false) do
    with :people <- config().paths,
         %User{} = user <- Repo.get_by(User, handle: handle) do
      {:person, user, by(user)}
    else
      _ -> :page
    end
  end

  defp person(_words, _feed?), do: :page

  @doc "A person's published pages and blogs, the latest first: their index."
  def by(%User{id: id}) do
    pages =
      Repo.all(
        from p in Page,
          left_join: f in assoc(p, :folder),
          where:
            p.published_by_id == ^id and not is_nil(p.published_at) and is_nil(p.archived_at),
          where: is_nil(f.published_at),
          order_by: [desc: p.published_at],
          preload: [:published_by, :folder]
      )

    blogs =
      Repo.all(
        from f in Folder,
          where: f.published_by_id == ^id and not is_nil(f.published_at),
          order_by: [desc: f.published_at],
          preload: :published_by
      )

    %{pages: pages, blogs: blogs}
  end

  @doc "A person's index: the path of their handle, by person."
  def person_url(%User{handle: handle}), do: config().url <> config().prefix <> "/" <> handle

  defp strip_prefix(words) do
    prefix = config().prefix |> String.split("/", trim: true)
    if List.starts_with?(words, prefix), do: Enum.drop(words, length(prefix)), else: words
  end

  defp find(slug) do
    page =
      Repo.one(
        from p in Page,
          where: p.slug == ^slug and not is_nil(p.published_at) and is_nil(p.archived_at)
      )

    folder =
      page || Repo.one(from f in Folder, where: f.slug == ^slug and not is_nil(f.published_at))

    cond do
      page -> {:page, Repo.preload(page, [:author, :published_by, :folder])}
      folder -> {:blog, Repo.preload(folder, :published_by)}
      true -> nil
    end
  end

  @doc "A blog's posts: its published pages, the latest first."
  def posts(%Folder{id: id}) do
    from(p in Page,
      where: p.folder_id == ^id and not is_nil(p.published_at) and is_nil(p.archived_at),
      order_by: [desc: p.published_at, desc: p.id],
      preload: [:author, :published_by, :folder]
    )
    |> Repo.all()
  end

  @doc "A person's published pages and blogs, for the notebook's lists."
  def published(%Scope{} = scope) do
    Page
    |> Notebook.Permissions.where_allowed(scope, :read)
    |> where([p], not is_nil(p.published_at) and is_nil(p.archived_at))
    |> order_by([p], desc: p.published_at)
    |> Repo.all()
  end

  ## A public page's parts

  @doc "Whether a file may be read by anyone: a published page shows it."
  def public_upload?(key) when is_binary(key) do
    pattern = "%" <> String.replace(key, ~w(% _ \\), &("\\" <> &1)) <> "%"

    Repo.exists?(
      from p in Page,
        where: not is_nil(p.published_at) and is_nil(p.archived_at),
        where: fragment("CAST(? AS TEXT) LIKE ? ESCAPE '\\'", p.body, ^pattern)
    )
  end

  @doc """
  A page's content as a public page reads it: its files at the notebook's
  own address, so that they load wherever the page is read.
  """
  def absolute_files(%Kotoba.Content{doc: doc} = content),
    do: %{content | doc: absolute(doc, NotebookWeb.Endpoint.url())}

  def absolute_files(content), do: content

  defp absolute("/uploads/" <> _ = path, base), do: base <> path

  defp absolute(map, base) when is_map(map),
    do: Map.new(map, fn {k, v} -> {k, absolute(v, base)} end)

  defp absolute(list, base) when is_list(list), do: Enum.map(list, &absolute(&1, base))
  defp absolute(other, _base), do: other

  @doc """
  Whether a socket's origin may connect to the public pages' live socket:
  the notebook's own address, or the publishing one.
  """
  def origin?(%URI{host: host}) do
    host in [NotebookWeb.Endpoint.host(), URI.parse(config().url).host]
  end

  ## Feeds

  @doc "A blog's RSS feed."
  def feed(%Folder{} = folder, posts) do
    %{name: site} = config()

    items =
      Enum.map_join(posts, "\n", fn post ->
        """
            <item>
              <title>#{escape(post.title)}</title>
              <link>#{escape(url(post))}</link>
              <guid isPermaLink="true">#{escape(url(post))}</guid>
              <pubDate>#{rfc822(post.published_at)}</pubDate>
              <description>#{escape(summary(post))}</description>
            </item>
        """
      end)

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
      <channel>
        <title>#{escape(folder.name)} · #{escape(site)}</title>
        <link>#{escape(url(folder))}</link>
        <atom:link href="#{escape(feed_url(folder))}" rel="self" type="application/rss+xml" />
        <description>#{escape(folder.name)}</description>
    #{items}
      </channel>
    </rss>
    """
  end

  @doc "A page's first words, for a feed or a blog's list."
  def summary(%Page{kind: "text", body: %Kotoba.Content{text: text}}) when is_binary(text) do
    text = text |> String.replace(~r/\s+/, " ") |> String.trim()
    if String.length(text) > 280, do: String.slice(text, 0, 279) <> "…", else: text
  end

  def summary(_page), do: ""

  defp rfc822(%DateTime{} = at), do: Calendar.strftime(at, "%a, %d %b %Y %H:%M:%S +0000")

  defp escape(text),
    do: text |> to_string() |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
