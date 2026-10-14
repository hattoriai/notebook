defmodule Notebook.PagesDatesTest do
  use Notebook.DataCase, async: true

  alias Notebook.{Accounts, Pages}
  alias Notebook.Accounts.Scope
  alias Notebook.Pages.Page

  setup do
    {:ok, user} =
      Accounts.register_user(%{
        name: "Nina Writer",
        email: "nina-dates@example.test",
        password: "long enough password"
      })

    %{scope: Scope.for_user(user)}
  end

  test "a page keeps its dates in SQLite", %{scope: scope} do
    {:ok, page} =
      Pages.create(scope, %{
        "title" => "Lisbon trip",
        "due_on" => "2027-03-12",
        "covers" => %{"from" => "2027-03-15", "to" => "2027-03-19"},
        "review_at" => "2027-03-10T14:00:00Z",
        "revisit" => "FREQ=WEEKLY;BYDAY=MO"
      })

    page = Pages.get!(page.id)
    assert page.due_on == ~D[2027-03-12]
    assert page.covers == Date.range(~D[2027-03-15], ~D[2027-03-19])
    assert page.review_at == ~U[2027-03-10 14:00:00Z]
    assert Koyomi.Recurrence.to_string(page.revisit) == "FREQ=WEEKLY;BYDAY=MO"

    # The range is an ISO 8601 interval in a text column.
    %{rows: [[covers]]} = Repo.query!("SELECT covers FROM pages WHERE id = ?", [page.id])
    assert covers == "2027-03-15/2027-03-19"
  end

  test "a review time without an offset is read on Lisbon's wall clock", %{scope: scope} do
    # As the browser's own input posts it with JavaScript off; Lisbon is on
    # summer time (UTC+1) in July.
    {:ok, page} = Pages.create(scope, %{"title" => "Summer", "review_at" => "2027-07-15T14:00"})
    assert page.review_at == ~U[2027-07-15 13:00:00Z]
  end

  test "the review rules refuse a weekend and the night" do
    saturday = Page.changeset(%Page{}, %{"title" => "A", "review_at" => "2027-03-13T14:00:00Z"})
    assert errors_on(saturday)[:review_at]

    night = Page.changeset(%Page{}, %{"title" => "A", "review_at" => "2027-03-15T22:00:00Z"})
    assert errors_on(night)[:review_at]

    ok = Page.changeset(%Page{}, %{"title" => "A", "review_at" => "2027-03-15T14:00:00Z"})
    assert ok.valid?
  end

  test "a review in the past stays when another field changes" do
    page = %Page{title: "Old", review_at: ~U[2020-01-06 14:00:00Z]}
    assert Page.changeset(page, %{"title" => "Older"}).valid?
  end

  test "a range of days that ends before it starts is refused" do
    changeset =
      Page.changeset(%Page{}, %{
        "title" => "A",
        "covers" => %{"from" => "2027-03-19", "to" => "2027-03-15"}
      })

    assert errors_on(changeset)[:covers]
  end

  test "the agenda has each page's due day, covered days, review and revisits", %{scope: scope} do
    {:ok, page} =
      Pages.create(scope, %{
        "title" => "Trip",
        "due_on" => "2027-03-01",
        "covers" => %{"from" => "2027-03-10", "to" => "2027-03-11"},
        # Lisbon is on UTC in March, before the clocks go forward.
        "review_at" => "2027-03-03T10:00:00Z",
        "revisit" => "FREQ=WEEKLY;COUNT=3"
      })

    agenda = Pages.agenda([page], Date.range(~D[2027-03-01], ~D[2027-03-31]))
    kinds = Map.new(agenda, fn {day, items} -> {day, Enum.map(items, &elem(&1, 0))} end)

    assert kinds[~D[2027-03-01]] == [:due, :revisit]
    assert kinds[~D[2027-03-03]] == [:review]
    assert kinds[~D[2027-03-08]] == [:revisit]
    assert kinds[~D[2027-03-10]] == [:covers]
    assert kinds[~D[2027-03-15]] == [:revisit]
    assert kinds[~D[2027-03-22]] == nil

    assert Pages.on_day([page], ~D[2027-03-11]) == [page]
    assert Pages.on_day([page], ~D[2027-03-12]) == []
  end

  test "review slots are weekday hours, with the taken ones disabled", %{scope: scope} do
    {:ok, other} =
      Pages.create(scope, %{"title" => "Budget", "review_at" => "2027-03-15T11:00:00Z"})

    slots = Pages.review_slots(Date.range(~D[2027-03-13], ~D[2027-03-15]))
    refute Map.has_key?(slots, ~D[2027-03-13])
    refute Map.has_key?(slots, ~D[2027-03-14])

    monday = slots[~D[2027-03-15]]
    assert length(monday[:slots]) == 7
    assert %{time: ~T[11:00:00], disabled: true, label: "Taken: Budget"} in monday[:slots]
    assert monday[:title] == "6 free times"

    # A page's own review does not take its slot.
    slots = Pages.review_slots(Date.range(~D[2027-03-15], ~D[2027-03-15]), other.id)
    refute Enum.any?(slots[~D[2027-03-15]][:slots], &Map.get(&1, :disabled))
  end
end
