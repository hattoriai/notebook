defmodule Notebook.Webhooks do
  @moduledoc """
  The notebook's events, sent to the endpoints its admins add under
  Notebook settings → Webhooks ([Kunai](https://github.com/hattoriai/kunai)).

  The endpoints are the notebook's (one owner, `"notebook"`): an event is
  emitted in the transaction of the change it tells of, by whoever made it,
  a person, their agent or a bot. A page of a Private space is its
  person's alone, and sends nothing.
  """

  use Kunai.Catalog

  alias Notebook.Accounts.Scope
  alias Notebook.Pages.Page

  version("2026-10-01")

  @page [
    id: :string,
    title: :string,
    kind: :string,
    space: [id: :string, name: :string],
    folder_id: :string,
    author: [id: :string, name: :string],
    due_on: :date,
    archived_at: :datetime,
    published_at: :datetime,
    inserted_at: :datetime,
    updated_at: :datetime
  ]

  @example %{
    "id" => "1",
    "title" => "The forge, planned",
    "kind" => "board",
    "space" => %{"id" => "2", "name" => "The forge"},
    "folder_id" => nil,
    "author" => %{"id" => "1", "name" => "Hattori Hanzo"},
    "due_on" => nil,
    "archived_at" => nil,
    "published_at" => nil,
    "inserted_at" => "2026-10-26T09:00:00Z",
    "updated_at" => "2026-10-26T09:00:00Z"
  }

  @page_events ~w(page.created page.updated page.moved page.archived page.restored)

  event("page.created", doc: "A page was made.", schema: @page, example: @example)
  event("page.updated", doc: "A page's title or dates changed.", schema: @page, example: @example)

  event("page.moved",
    doc: "A page went to another space or folder.",
    schema: @page,
    example: @example
  )

  event("page.archived", doc: "A page was archived.", schema: @page, example: @example)
  event("page.restored", doc: "An archived page came back.", schema: @page, example: @example)

  @impl Kunai.Catalog
  def owner(_scope), do: "notebook"

  @impl Kunai.Catalog
  def actor(%Scope{agent: "bot:" <> id}), do: %{type: "bot", id: id}

  def actor(%Scope{agent: "agent:" <> id, user: user}),
    do: %{type: "agent", id: id, for: to_string(user.id)}

  def actor(%Scope{user: user}) when not is_nil(user),
    do: %{type: "user", id: to_string(user.id), name: user.name}

  def actor(_scope), do: nil

  @doc """
  Emits a page's event, unless the page is in a Private space. Called in
  the transaction of the change.
  """
  def page_event(type, scope, %Page{} = page, previous \\ nil) when type in @page_events do
    page = Notebook.Repo.preload(page, [:space, :author], force: true)

    if page.space.kind != "private" do
      Kunai.emit!(type, page(page), scope: scope, previous: previous)
    end

    :ok
  end

  @doc "A page as its events give it."
  def page(%Page{} = page) do
    %{
      id: to_string(page.id),
      title: page.title,
      kind: page.kind,
      space: %{id: to_string(page.space.id), name: page.space.name},
      folder_id: page.folder_id && to_string(page.folder_id),
      author: page.author && %{id: to_string(page.author.id), name: page.author.name},
      due_on: page.due_on,
      archived_at: page.archived_at,
      published_at: page.published_at,
      inserted_at: page.inserted_at,
      updated_at: page.updated_at
    }
  end
end
