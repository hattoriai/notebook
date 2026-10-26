defmodule Notebook.DatabasesTest do
  # SQLite takes one writer at a time: these write a lot, so they run alone.
  use Notebook.DataCase, async: false

  import Notebook.AccountsFixtures

  alias Notebook.Accounts.Scope
  alias Notebook.Cardbox, as: Box
  alias Notebook.Actions.AddRecords
  alias Notebook.Tools.{CreatePage, ListPages, ReadDatabase, UpdateRecords}
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

    # Adding records joins the agent to the page's room: it leaves after.
    on_exit(fn ->
      for user <- [hanzo, yuki],
          do: Issho.Agents.leave(Notebook.Issho, "agent:#{user.id}", "page:#{page.id}")
    end)

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

    test "paused by its person in the page's room, it adds and changes no record", %{
      hanzo: hanzo,
      page: page,
      collection: collection
    } do
      ctx = ctx(hanzo)
      room = Notebook.Collaboration.room(page)
      key = Issho.Tool.Context.key(ctx)
      {:ok, agent} = Issho.Tool.Context.join(ctx, room)

      try do
        by = %{id: to_string(hanzo.id), name: hanzo.name}
        :ok = Issho.Work.interrupt(Notebook.Issho, room, key, :pause, by: by)
        assert eventually(fn -> Issho.Participant.interrupted(agent) end)

        {:ok, [record | _]} = Box.list(collection, %{}, limit: 10)

        assert {:error, "Hattori Hanzo paused you." <> _} =
                 AddRecords.call(%{page_id: page.id, records: [%{"Name" => "Not now"}]}, ctx)

        assert {:error, "Hattori Hanzo paused you." <> _} =
                 UpdateRecords.call(
                   %{
                     page_id: page.id,
                     changes: [%{id: record.id, values: %{"Status" => "Asked"}}]
                   },
                   ctx
                 )

        {:ok, records} = Box.list(collection, %{}, limit: 10)
        assert length(records) == 2
        refute Enum.any?(records, &(&1.data["status"] == "asked"))
      after
        Issho.Agents.leave(Notebook.Issho, key, room)
      end
    end

    test "reads what its person reads, and changes what they edit", %{
      yuki: yuki,
      stranger: stranger,
      page: page
    } do
      assert {:ok, %{"editable" => false}} = ReadDatabase.call(%{page_id: page.id}, ctx(yuki))

      assert {:error, "The room's policy does not allow this."} =
               AddRecords.call(%{page_id: page.id, records: [%{"Name" => "No"}]}, ctx(yuki))

      assert {:error, "No database page of that id" <> _} =
               ReadDatabase.call(%{page_id: page.id}, ctx(stranger))
    end
  end

  describe "bills: money, files and repeats" do
    # The files a record kept, removed from the store after the test.
    defp discard(collection, id) do
      for %{"key" => key} <- Box.get(collection, id).data["invoice"] || [],
          do: Storehouse.Local.delete(key)
    end

    @pdf "%PDF-1.7\n1 0 obj << /Type /Catalog >> endobj\ntrailer << /Root 1 0 R >>\n%%EOF\n"

    test "a number field is money in a currency, and a repeat finds its date and status", %{
      scope: scope,
      collection: collection
    } do
      {:ok, collection} =
        Databases.add_field(scope, collection, %{
          "name" => "Amount",
          "type" => "number",
          "format" => "currency",
          "currency" => "eur"
        })

      assert %{options: %{"format" => "currency", "currency" => "EUR"}} =
               Cardbox.Collection.field(collection, "Amount")

      {:ok, collection} =
        Databases.add_field(scope, collection, %{"name" => "Repeats", "type" => "repeat"})

      assert %{options: %{"date" => "due", "done" => "status"}} =
               Cardbox.Collection.field(collection, "Repeats")

      {:ok, collection} =
        Databases.add_field(scope, collection, %{"name" => "Invoice", "type" => "file"})

      assert [{"invoice", "Invoice"}] = Databases.fields_of(collection, ["file"])
    end

    test "a file stored for a record is checked by its bytes, and attached after those it has", %{
      scope: scope,
      collection: collection
    } do
      {:ok, collection} =
        Databases.add_field(scope, collection, %{"name" => "Invoice", "type" => "file"})

      {:ok, record} = Box.insert(collection, %{"Name" => "Electricity"}, actor: scope)

      dir = Path.join(System.tmp_dir!(), "notebook-db-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      pdf = Path.join(dir, "edp.pdf")
      File.write!(pdf, @pdf)
      page = Path.join(dir, "page.pdf")
      File.write!(page, "<html><script>alert(1)</script></html>")

      {:ok, invoice} = Databases.store_file(pdf, "edp-2026-11.pdf", "application/pdf")
      {:ok, fake} = Databases.store_file(page, "invoice.pdf", "application/pdf")
      on_exit(fn -> Databases.discard_files([invoice, fake]) end)
      assert invoice.content_type == "application/pdf"
      assert fake.content_type == "application/octet-stream"
      assert invoice.url =~ ~r"^/uploads/kotoba/"

      {:ok, _} = Databases.attach(scope, collection, record.id, "invoice", [invoice])
      {:ok, record} = Databases.attach(scope, collection, record.id, "Invoice", [fake])

      assert [%{"name" => "edp-2026-11.pdf"}, %{"name" => "invoice.pdf"}] = record.data["invoice"]
    end

    test "an agent sends a file with a record, which is stored as an upload is", %{
      hanzo: hanzo,
      yuki: yuki,
      scope: scope,
      page: page,
      collection: collection
    } do
      {:ok, _} = Databases.add_field(scope, collection, %{"name" => "Invoice", "type" => "file"})

      assert {:ok, %{"records" => [%{"id" => id, "Invoice" => [invoice]}]}} =
               AddRecords.call(
                 %{
                   page_id: page.id,
                   records: [
                     %{
                       "Name" => "Electricity",
                       "Invoice" => [
                         %{"name" => "edp-2026-11.pdf", "data" => Base.encode64(@pdf)}
                       ]
                     }
                   ]
                 },
                 ctx(hanzo)
               )

      on_exit(fn -> discard(collection, id) end)

      assert %{"name" => "edp-2026-11.pdf", "content_type" => "application/pdf", "url" => url} =
               invoice

      assert url =~ ~r"^/uploads/kotoba/"

      # A file field's value is all its files: the one it has, and a new one.
      assert {:ok, %{"records" => [%{"Invoice" => [_, %{"name" => "receipt.pdf"}]}]}} =
               UpdateRecords.call(
                 %{
                   page_id: page.id,
                   changes: [
                     %{
                       id: id,
                       values: %{
                         "Invoice" => [
                           invoice,
                           %{"name" => "receipt.pdf", "data" => Base.encode64(@pdf)}
                         ]
                       }
                     }
                   ]
                 },
                 ctx(hanzo)
               )

      assert {:error, "receipt.pdf's data is not base64."} =
               UpdateRecords.call(
                 %{
                   page_id: page.id,
                   changes: [
                     %{
                       id: id,
                       values: %{"Invoice" => [%{"name" => "receipt.pdf", "data" => "%%"}]}
                     }
                   ]
                 },
                 ctx(hanzo)
               )

      # Someone who reads the page only stores nothing.
      assert {:error, "The room's policy does not allow this."} =
               AddRecords.call(
                 %{
                   page_id: page.id,
                   records: [
                     %{"Invoice" => [%{"name" => "x.pdf", "data" => Base.encode64(@pdf)}]}
                   ]
                 },
                 ctx(yuki)
               )
    end

    test "a bill paid comes back next month", %{scope: scope, collection: collection} do
      {:ok, collection} =
        Databases.add_field(scope, collection, %{"name" => "Repeats", "type" => "repeat"})

      {:ok, bill} =
        Box.insert(
          collection,
          %{"Name" => "Water", "Due" => ~D[2026-11-12], "Repeats" => "FREQ=MONTHLY"},
          actor: scope
        )

      {:ok, _} = Box.update(collection, bill.id, %{"Status" => "Done"}, actor: scope)

      {:ok, waters} =
        Box.list(collection, %{"filter" => %{"field" => "Name", "op" => "eq", "value" => "Water"}})

      assert ["2026-11-12", "2026-12-12"] == waters |> Enum.map(& &1.data["due"]) |> Enum.sort()
    end
  end

  defp eventually(fun, tries \\ 50) do
    case fun.() do
      nil when tries > 0 -> Process.sleep(10) && eventually(fun, tries - 1)
      result -> result
    end
  end
end
