defmodule Notebook.SearchTest do
  # SQLite takes one writer at a time: these write a lot, so they run alone.
  use Notebook.DataCase, async: false

  import Notebook.AccountsFixtures

  alias Notebook.Accounts.Scope
  alias Notebook.Cardbox, as: Box
  alias Notebook.{Databases, Pages, Repo, Search, Spaces}

  setup do
    hanzo = user_fixture(%{name: "Hattori Hanzo"})
    yuki = user_fixture(%{name: "Yuki Hattori"})
    scope = Scope.for_user(hanzo)
    {:ok, forge} = Spaces.create_team(scope, %{name: "The forge"})

    {:ok, menu} =
      Pages.create(scope, %{
        "title" => "Autumn menu",
        "space_id" => forge.id,
        "body" => Kotoba.Content.from_markdown("Hōjicha, roasted, for the evenings.")
      })

    {:ok, forge_page} =
      Pages.create(scope, %{
        "title" => "The forge",
        "space_id" => forge.id,
        "body" => Kotoba.Content.from_markdown("Where the tea is too strong.")
      })

    %{hanzo: hanzo, yuki: yuki, scope: scope, forge: forge, menu: menu, forge_page: forge_page}
  end

  defp titles(scope, query), do: scope |> Search.search(query) |> Enum.map(& &1.page.title)

  test "a word finds its pages without case or accents, and as a word's start", %{scope: scope} do
    assert ["Autumn menu"] == titles(scope, "hojicha")
    assert ["Autumn menu"] == titles(scope, "HŌJI")
    assert ["The forge"] == titles(scope, "forg")
    assert [] == titles(scope, "katana")
    assert [] == titles(scope, "  ")
    # A query is words, never FTS5's operators.
    assert [] == titles(scope, ~s(" OR NEAR\(\) *))
  end

  test "a title weighs more than a text, and the words around what matched come with it", %{
    scope: scope
  } do
    assert ["The forge", "Autumn menu"] = titles(scope, "the")
    assert [%{snippet: parts}] = Search.search(scope, "roasted")
    assert {"roasted", true} in parts
  end

  test "only the pages the scope may read, and not those archived", %{
    scope: scope,
    yuki: yuki,
    menu: menu
  } do
    assert [] == titles(Scope.for_user(yuki), "hojicha")

    {:ok, _} = Pages.archive(scope, menu)
    assert [] == titles(scope, "hojicha")

    assert ["Autumn menu"] ==
             scope |> Search.search("hojicha", archived: true) |> Enum.map(& &1.page.title)
  end

  test "a page's words follow it as it changes", %{scope: scope, menu: menu} do
    {:ok, _} = Pages.update(scope, menu, %{"title" => "Winter menu"})
    assert ["Winter menu"] == titles(scope, "winter")

    {:ok, _} = Pages.publish(scope, menu, Kotoba.Content.from_markdown("Genmaicha now."))
    assert [] == titles(scope, "hojicha")
    assert ["Winter menu"] == titles(scope, "genmaicha")

    Repo.delete!(Repo.get!(Notebook.Pages.Page, menu.id))
    assert [] == titles(scope, "genmaicha")
  end

  test "a table's rows and a database's records are their page's words", %{
    scope: scope,
    forge: forge
  } do
    {:ok, table} =
      Pages.create(scope, %{"title" => "Blades", "kind" => "table", "space_id" => forge.id})

    Repo.insert!(%Notebook.Pages.Row{
      page_id: table.id,
      title: "The rain blade",
      owner: "Masamune"
    })

    assert ["Blades"] == titles(scope, "masamune")

    {:ok, db} =
      Pages.create(scope, %{
        "title" => "Commissions",
        "kind" => "database",
        "space_id" => forge.id
      })

    {:ok, record} =
      Box.insert(Databases.collection(db), %{"Name" => "A tantō for a wedding"}, actor: scope)

    assert ["Commissions"] == titles(scope, "wedding")

    {:ok, _} = Box.delete(Databases.collection(db), record, actor: scope)
    assert [] == titles(scope, "wedding")
  end

  test "the pages a search lists are its best first", %{scope: scope} do
    assert ["The forge", "Autumn menu"] ==
             scope |> Pages.list(search: "the") |> Enum.map(& &1.title)
  end
end
