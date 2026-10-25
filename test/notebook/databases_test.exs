defmodule Notebook.DatabasesTest do
  # SQLite takes one writer at a time: these write a lot, so they run alone.
  use Notebook.DataCase, async: false

  import Notebook.AccountsFixtures

  alias Notebook.Accounts.Scope
  alias Notebook.Cardbox, as: Box
  alias Notebook.Tools.{AddRecords, CreatePage, ListPages, ReadDatabase, UpdateRecords}
  alias Notebook.{Databases, Pages, Spaces}

  setup do
    hanzo = user_fixture(%{name: "Hattori Hanzo"})
    yuki = user_fixture(%{name: "Yuki Hattori"})
    stranger = user_fixture(%{name: "A stranger"})
    scope = Scope.for_user(hanzo)
    {:ok, forge} = Spaces.create_team(scope, %{name: "The forge"})
    {:ok, _} = Spaces.add_member(scope, forge, yuki, "commenter")

    {:ok, page} =
      Pages.create(scope, %{
        "title" => "Commissions",
        "kind" => "database",
        "space_id" => forge.id
      })

    collection = Databases.collection(page)

    {:ok, _} =
      Box.insert(collection, %{"Name" => "The rain blade", "Status" => "Done"}, actor: scope)

    {:ok, _} =
      Box.insert(collection, %{"Name" => "A tantō", "Owner" => "user:#{hanzo.id}"}, actor: scope)

    %{
      hanzo: hanzo,
      yuki: yuki,
      stranger: stranger,
      scope: scope,
      page: page,
      collection: collection
    }
  end

  # An agent's context, as NotebookWeb.MCP makes it for a person's token.
  defp ctx(user) do
    Issho.Tool.Context.new(
      Notebook.Issho,
      %{id: "agent:#{user.id}", name: "Claude Code", kind: :agent},
      on_behalf_of: user
    )
  end

  describe "a database page" do
    test "starts with its fields and a view of each type", %{collection: collection} do
      assert ~w(Name Status Owner Due Tags) == Enum.map(collection.fields, & &1.name)

      views = Databases.views(collection)
      assert ~w(table board calendar chart) == Enum.map(views, & &1.type)

      board = Enum.find(views, &(&1.type == "board"))
      assert board.options["group_by"] == "status"
      assert board.options["card_fields"] == ~w(owner due tags)
    end

    test "is changed by its page's editors only", %{
      yuki: yuki,
      scope: scope,
      collection: collection
    } do
      yuki = Scope.for_user(yuki)

      assert {:error, %Cardbox.Error{reason: :unauthorized}} =
               Box.insert(collection, %{"Name" => "No"}, actor: yuki)

      assert {:error, _} =
               Databases.add_field(yuki, collection, %{"name" => "Price", "type" => "number"})

      assert {:ok, collection} =
               Databases.add_field(scope, collection, %{"name" => "Price", "type" => "number"})

      assert Enum.any?(collection.fields, &(&1.name == "Price"))
    end

    test "adds a view a field allows", %{scope: scope, page: page} do
      {:ok, bare} =
        Pages.create(scope, %{
          "title" => "Words",
          "kind" => "database",
          "space_id" => page.space_id,
          "fields" => [%{name: "Word", type: "text"}]
        })

      bare = Databases.collection(bare)
      assert ["table"] == Enum.map(Databases.views(bare), & &1.type)

      assert {:error, "A board needs a field it can use: add one first."} =
               Databases.add_view(scope, bare, "board")

      assert {:ok, %{type: "chart"}} =
               Databases.add_view(scope, Databases.collection(page), "chart")
    end

    test "offers its space's members as people", %{page: page, hanzo: hanzo, yuki: yuki} do
      assert [
               %{id: "user:#{hanzo.id}", name: "Hattori Hanzo"},
               %{id: "user:#{yuki.id}", name: "Yuki Hattori"}
             ] ==
               Databases.people(page)
    end
  end

  describe "an agent" do
    test "finds a database, and makes one", %{hanzo: hanzo, page: page} do
      {:ok, %{"pages" => pages}} = ListPages.call(%{}, ctx(hanzo))

      assert %{"kind" => "database", "use" => %{"page_id" => id}} =
               Enum.find(pages, &(&1["title"] == "Commissions"))

      assert id == page.id

      assert {:ok, %{"kind" => "database", "id" => id}} =
               CreatePage.call(%{title: "Reading list", kind: "database"}, ctx(hanzo))

      assert {:ok, %{"records" => []}} = ReadDatabase.call(%{page_id: id}, ctx(hanzo))
    end

    test "reads a database's fields, views and records, by a view or a filter", %{
      hanzo: hanzo,
      page: page
    } do
      {:ok, read} = ReadDatabase.call(%{page_id: page.id}, ctx(hanzo))
      assert read["editable"]
      assert "status" in Enum.map(read["fields"], & &1["key"])
      assert "Board" in Enum.map(read["views"], & &1["name"])
      assert ["The rain blade", "A tantō"] == Enum.map(read["records"], & &1["Name"])

      mine = %{"field" => "Owner", "op" => "eq", "value" => "me"}

      {:ok, read} =
        ReadDatabase.call(%{page_id: page.id, view: "Table", filter: mine}, ctx(hanzo))

      assert [%{"Name" => "A tantō", "Owner" => owner}] = read["records"]
      assert owner == "user:#{hanzo.id}"

      assert {:error, "No view of that name" <> _} =
               ReadDatabase.call(%{page_id: page.id, view: "Gallery"}, ctx(hanzo))
    end

    test "adds and changes records as its person", %{
      hanzo: hanzo,
      page: page,
      collection: collection
    } do
      assert {:ok,
              %{"records" => [%{"id" => id, "Name" => "A pair for the dojo", "Status" => nil}]}} =
               AddRecords.call(
                 %{page_id: page.id, records: [%{"Name" => "A pair for the dojo"}]},
                 ctx(hanzo)
               )

      assert {:ok, %{"records" => [%{"Status" => "In progress"}]}} =
               UpdateRecords.call(
                 %{page_id: page.id, changes: [%{id: id, values: %{"Status" => "In progress"}}]},
                 ctx(hanzo)
               )

      assert %{created_by: by} = Box.get(collection, id)
      assert by == "user:#{hanzo.id}"
    end

    test "reads what its person reads, and changes what they edit", %{
      yuki: yuki,
      stranger: stranger,
      page: page
    } do
      assert {:ok, %{"editable" => false}} = ReadDatabase.call(%{page_id: page.id}, ctx(yuki))

      assert {:error, "The person you work for may not change this database" <> _} =
               AddRecords.call(%{page_id: page.id, records: [%{"Name" => "No"}]}, ctx(yuki))

      assert {:error, "No database page of that id" <> _} =
               ReadDatabase.call(%{page_id: page.id}, ctx(stranger))
    end
  end
end
