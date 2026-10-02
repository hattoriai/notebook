defmodule Notebook.Pages do
  @moduledoc """
  The pages of the notebook. Notebook is one shared space: every signed-in
  account reads and edits every page. A page keeps the account that made it
  as its author.
  """
  import Ecto.Query
  alias Notebook.Accounts.Scope
  alias Notebook.Pages.Page
  alias Notebook.Repo

  def list(query \\ "") do
    search = "%" <> String.trim(query) <> "%"

    from(d in Page,
      where:
        like(d.title, ^search) or
          fragment("coalesce(json_extract(?, '$.text'), '') LIKE ?", d.body, ^search),
      order_by: [desc: d.updated_at],
      preload: :author
    )
    |> Repo.all()
  end

  def get!(id), do: Page |> Repo.get!(id) |> Repo.preload(:author)
  def get(id), do: Repo.get(Page, id)
  def change(page, attrs \\ %{}), do: Page.changeset(page, attrs)
  @doc "Creates a page with the scope's user as its author."
  def create(%Scope{user: user}, attrs) do
    %Page{author_id: user.id}
    |> Page.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, page} -> {:ok, Repo.preload(page, :author)}
      error -> error
    end
  end

  def update(page, attrs) do
    with {:ok, page} <- page |> Page.changeset(attrs) |> Repo.update(),
         do: {:ok, Repo.preload(page, :author, force: true)}
  end

  def publish(page, content) do
    page
    |> Ecto.Changeset.change(body: content)
    |> Repo.update()
  end

  def mentions(query) do
    list(query)
    |> Enum.take(20)
    |> Enum.map(&%{id: &1.id, label: &1.title, hint: "Page"})
  end
end
