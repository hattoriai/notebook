defmodule Notebook.Cardbox.RepeatTest do
  # SQLite takes one writer at a time: these write a lot, so they run alone.
  use Notebook.DataCase, async: false

  alias Cardbox.{Collection, Error, Field}
  alias Notebook.Cardbox, as: Box
  alias Notebook.Cardbox.Repeat

  @invoice %{
    key: "k",
    url: "/uploads/kotoba/k.pdf",
    name: "edp.pdf",
    content_type: "application/pdf"
  }

  import Notebook.AccountsFixtures

  setup do
    scope = Notebook.Accounts.Scope.for_user(user_fixture(%{name: "Hattori Hanzo"}))
    Process.put(:scope, scope)
    %{scope: scope}
  end

  # A database page's collection, with these fields only.
  defp database!(title, fields) do
    scope = Process.get(:scope)

    {:ok, space} =
      Notebook.Spaces.create_team(scope, %{name: "#{title} #{System.unique_integer([:positive])}"})

    {:ok, page} =
      Notebook.Pages.create(scope, %{
        "title" => title,
        "kind" => "database",
        "space_id" => space.id
      })

    collection = Notebook.Databases.collection(page)

    collection =
      Enum.reduce(collection.fields, collection, fn field, c ->
        {:ok, c} = Box.delete_field(c, field, actor: scope)
        c
      end)

    Enum.reduce(fields, collection, fn field, c ->
      {:ok, c} = Box.add_field(c, field, actor: scope)
      c
    end)
  end

  defp bills! do
    database!("Bills", [
      %{name: "Payee", type: "text"},
      %{name: "Amount", type: "number", options: %{format: "currency", currency: "EUR"}},
      %{name: "Due", type: "date"},
      %{name: "Status", type: "status"},
      %{name: "Invoice", type: "file"},
      %{name: "Repeats", type: "repeat", options: %{date: "Due", done: "Status"}}
    ])
  end

  defp insert!(collection, values) do
    {:ok, record} = Box.insert(collection, values, actor: Process.get(:scope))
    record
  end

  defp change(collection, id, values),
    do: Box.update(collection, id, values, actor: Process.get(:scope))

  defp by_due(collection, field \\ "Due") do
    {:ok, records} = Box.list(collection, %{"sort" => [%{"field" => field}]})
    records
  end

  test "a field names its date and done fields, kept by key" do
    collection = bills!()

    assert %Field{options: %{"date" => "due", "done" => "status"}} =
             Collection.field(collection, "Repeats")

    assert {:error, %Error{errors: [{"options", "a repeat's date is a date field" <> _}]}} =
             Box.add_field(
               collection,
               %{
                 name: "Again",
                 type: "repeat",
                 options: %{date: "Payee", done: "Status"}
               },
               actor: Process.get(:scope)
             )

    assert {:error, %Error{errors: [{"options", "a repeat names its done field" <> _}]}} =
             Box.add_field(
               collection,
               %{
                 name: "Again",
                 type: "repeat",
                 options: %{date: "Due", done: "Nope"}
               },
               actor: Process.get(:scope)
             )

    assert {:error, %Error{errors: [{"options", "a repeat names its date field" <> _}]}} =
             Box.add_field(collection, %{name: "Again", type: "repeat"},
               actor: Process.get(:scope)
             )
  end

  test "a rule is checked, kept in one form, and read in words" do
    collection = bills!()
    record = insert!(collection, %{"Repeats" => "rrule:byday=fr;freq=weekly"})
    assert record.data["repeats"] == "FREQ=WEEKLY;BYDAY=FR"

    assert {:error, %Error{errors: [{"repeats", "is a rule of days, as RRULE" <> _}]}} =
             Box.insert(collection, %{"Repeats" => "every month"}, actor: Process.get(:scope))

    assert Repeat.describe("FREQ=MONTHLY") == "Monthly"
    assert Repeat.describe("FREQ=YEARLY", "pt-PT") =~ "ano"

    %{"properties" => %{"repeats" => %{"anyOf" => [%{"type" => "string"}, _]}}} =
      Cardbox.JSONSchema.schema(collection)
  end

  test "a bill paid comes back next month, to pay, without its invoice" do
    collection = bills!()

    bill =
      insert!(collection, %{
        "Payee" => "EDP",
        "Amount" => 62.4,
        "Due" => ~D[2026-11-05],
        "Status" => "Not started",
        "Invoice" => @invoice,
        "Repeats" => "FREQ=MONTHLY"
      })

    :ok = Box.subscribe(collection)
    {:ok, _} = change(collection, bill.id, %{"Status" => "Done"})
    assert_receive {:cardbox, %Cardbox.Event{type: :record_inserted, record: %{id: id}}}

    assert [_paid, %{id: ^id} = next] = by_due(collection)

    assert next.data == %{
             "payee" => "EDP",
             "amount" => 62.4,
             "due" => "2026-12-05",
             "status" => "not_started",
             "repeats" => "FREQ=MONTHLY"
           }

    # Done already: a change that leaves it done makes no other.
    {:ok, _} = change(collection, bill.id, %{"Amount" => 63})
    assert Box.count(collection, nil) == {:ok, 2}
  end

  test "a COUNT runs out, a checkbox is unticked, and no rule or no date makes none" do
    collection =
      database!("Chores", [
        %{name: "What", type: "text"},
        %{name: "When", type: "date"},
        %{name: "Done", type: "checkbox"},
        %{name: "Every", type: "repeat", options: %{date: "When", done: "Done"}}
      ])

    chore =
      insert!(collection, %{
        "What" => "Water the bonsai",
        "When" => ~D[2026-11-02],
        "Every" => "FREQ=WEEKLY;COUNT=2"
      })

    {:ok, _} = change(collection, chore.id, %{"Done" => true})
    [_, second] = by_due(collection, "When")
    assert second.data["when"] == "2026-11-09"
    assert second.data["every"] == "FREQ=WEEKLY;COUNT=1"
    refute Map.has_key?(second.data, "done")

    {:ok, _} = change(collection, second.id, %{"Done" => true})
    assert Box.count(collection, nil) == {:ok, 2}

    no_rule = insert!(collection, %{"What" => "Once", "When" => ~D[2026-11-02]})
    no_date = insert!(collection, %{"What" => "Someday", "Every" => "FREQ=DAILY"})
    {:ok, _} = change(collection, no_rule.id, %{"Done" => true})
    {:ok, _} = change(collection, no_date.id, %{"Done" => true})
    assert Box.count(collection, nil) == {:ok, 4}
  end

  test "undone and done again is another occurrence; the last day of a month stays the last" do
    collection = bills!()

    bill =
      insert!(collection, %{"Due" => ~D[2026-01-31], "Repeats" => "FREQ=MONTHLY;BYMONTHDAY=-1"})

    {:ok, _} = change(collection, bill.id, %{"Status" => "Done"})
    {:ok, _} = change(collection, bill.id, %{"Status" => "In progress"})
    {:ok, _} = change(collection, bill.id, %{"Status" => "Done"})

    assert Enum.map(by_due(collection), & &1.data["due"]) == [
             "2026-01-31",
             "2026-02-28",
             "2026-02-28"
           ]
  end
end
