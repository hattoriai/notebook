defmodule Notebook.NotificationsTest do
  # SQLite takes one writer at a time: these write a lot, so they run alone.
  use Notebook.DataCase, async: false

  import Chime.Test
  import Notebook.AccountsFixtures

  alias Notebook.Accounts.Scope
  alias Notebook.Cardbox, as: Box
  alias Notebook.Notifications

  alias Notebook.Notifications.{
    AddedToSpace,
    Assigned,
    Due,
    Mentioned,
    RecordDue,
    Replied,
    Review
  }

  alias Notebook.{Collaboration, Databases, Pages, Spaces}

  setup do
    hanzo = user_fixture(%{name: "Hattori Hanzo"})
    masamune = user_fixture(%{name: "Okazaki Masamune"})
    yuki = user_fixture(%{name: "Yuki Hattori"})
    scope = Scope.for_user(hanzo)
    {:ok, forge} = Spaces.create_team(scope, %{name: "The forge"})
    {:ok, _} = Spaces.add_member(scope, forge, masamune, "editor")
    {:ok, blade} = Pages.create(scope, %{"title" => "The last blade", "space_id" => forge.id})

    # Each test's ids are the last one's (its rows are rolled back), and
    # Issho's documents outlive a test: none of the last one's goes on.
    stop(Issho.Comments.document(Collaboration.room(blade)))
    for user <- [hanzo, masamune, yuki], do: stop(Issho.Inbox.document(to_string(user.id)))

    %{hanzo: hanzo, masamune: masamune, yuki: yuki, scope: scope, forge: forge, blade: blade}
  end

  defp stop(document) do
    case Issho.Documents.whereis(Notebook.Issho, document) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end
  end

  defp as(user), do: %{id: user.id, name: user.name}

  defp comment(page, by, body, opts \\ []) do
    {:ok, ids} =
      Issho.Comments.start(Notebook.Issho, Collaboration.room(page), as(by), nil, body, opts)

    Notifications.settle()
    ids
  end

  defp reply(page, by, thread, body) do
    {:ok, _} =
      Issho.Comments.reply(Notebook.Issho, Collaboration.room(page), as(by), thread, body)

    Notifications.settle()
  end

  test "someone added to a space hears of it, from whom", %{masamune: masamune} do
    notification =
      assert_notified(AddedToSpace,
        to: masamune,
        data: %{"space" => "The forge", "role" => "editor"}
      )

    assert [%{"name" => "Hattori Hanzo"}] = notification.actors

    assert [%{title: "Hattori Hanzo added you to The forge", body: "You're an editor there."}] =
             feed(masamune)
  end

  test "a mention tells the person mentioned, not its author", %{
    hanzo: hanzo,
    masamune: masamune,
    blade: blade
  } do
    comment(blade, masamune, "@Hattori Hanzo, one more quench?", mentions: [to_string(hanzo.id)])

    assert_notified(Mentioned,
      to: hanzo,
      data: %{"page" => "The last blade", "body" => "@Hattori Hanzo, one more quench?"}
    )

    refute_notified(Mentioned, to: masamune)

    assert %{title: "Okazaki Masamune mentioned you in The last blade", url: url} =
             Enum.find(feed(hanzo), &(&1.kind == "mentioned"))

    assert url == "/pages/#{blade.id}"
  end

  test "a person may not hear of a page they may not read", %{
    masamune: masamune,
    yuki: yuki,
    blade: blade
  } do
    comment(blade, masamune, "@Yuki, look", mentions: [to_string(yuki.id)])
    assert feed(yuki) == []
  end

  test "a reply tells the others in the thread, one notification for the thread's replies", %{
    hanzo: hanzo,
    masamune: masamune,
    blade: blade
  } do
    %{thread: thread} = comment(blade, hanzo, "Thursday, at dawn?")
    reply(blade, masamune, thread, "At dawn.")

    assert_notified(Replied, to: hanzo, data: %{"body" => "At dawn."})
    refute_notified(Replied, to: masamune)

    reply(blade, masamune, thread, "I'll bring the charcoal.")

    assert [%{title: "Okazaki Masamune replied in The last blade", count: 2}] =
             Enum.filter(feed(hanzo), &(&1.kind == "replied"))
  end

  test "a record given to someone tells them, but not the one who gave it", %{
    scope: scope,
    hanzo: hanzo,
    masamune: masamune,
    forge: forge
  } do
    {:ok, page} =
      Pages.create(scope, %{
        "title" => "Commissions",
        "kind" => "database",
        "space_id" => forge.id
      })

    collection = Databases.collection(page)

    {:ok, record} =
      Box.insert(collection, %{"Name" => "A tantō", "Owner" => "user:#{masamune.id}"},
        actor: scope
      )

    Notifications.settle()

    assert_notified(Assigned,
      to: masamune,
      data: %{"title" => "A tantō", "page" => "Commissions"}
    )

    {:ok, _} = Box.update(collection, record, %{"Owner" => "user:#{hanzo.id}"}, actor: scope)
    Notifications.settle()
    refute_notified(Assigned, to: hanzo)
  end

  test "a page due today reminds its author at 09:00 of the day, and a new day replaces it", %{
    scope: scope,
    hanzo: hanzo,
    forge: forge
  } do
    tomorrow = Date.add(Date.utc_today(), 1)

    {:ok, page} =
      Pages.create(scope, %{
        "title" => "A reply to the museum",
        "space_id" => forge.id,
        "due_on" => tomorrow
      })

    assert [%{status: "scheduled"}] = events(Due)

    {:ok, _} = Pages.update(scope, page, %{"due_on" => Date.add(tomorrow, 7)})
    assert ["cancelled", "scheduled"] == events(Due) |> Enum.map(& &1.status) |> Enum.sort()

    run_scheduled(DateTime.add(DateTime.utc_now(), 3, :day))
    refute_notified(Due, to: hanzo)

    run_scheduled(DateTime.add(DateTime.utc_now(), 9, :day))
    assert_notified(Due, to: hanzo, data: %{"due_on" => Date.to_iso8601(Date.add(tomorrow, 7))})
  end

  test "a review time reminds the page's author", %{hanzo: hanzo, blade: blade} do
    at = DateTime.utc_now() |> DateTime.add(2, :day) |> DateTime.truncate(:second)
    page = Ecto.Changeset.change(blade, review_at: at) |> Notebook.Repo.update!()
    Notifications.remind(page)

    run_scheduled(DateTime.add(at, 1, :minute))
    assert_notified(Review, to: hanzo, data: %{"page" => "The last blade"})
  end

  test "the email waits ten minutes, and doesn't go when the notification was read", %{
    hanzo: hanzo,
    masamune: masamune,
    yuki: yuki,
    scope: scope,
    forge: forge,
    blade: blade
  } do
    comment(blade, masamune, "@Hattori Hanzo, one more quench?", mentions: [to_string(hanzo.id)])
    assert [] == deliver(channel: :email, to: hanzo)

    later = DateTime.add(DateTime.utc_now(), 11, :minute)
    assert Enum.any?(deliver(at: later, to: hanzo), &(&1.status == "sent"))
    assert_received {:email, %{subject: "Okazaki Masamune mentioned you in The last blade"}}

    {:ok, _} = Spaces.add_member(scope, forge, yuki, "viewer")
    [%{id: id}] = feed(yuki)
    Chime.mark_read(Notifications.id(yuki), [id])

    assert [%{status: "skipped", reason: "read in the feed" <> _}] = deliver(at: later, to: yuki)
  end

  describe "a record's day" do
    setup %{scope: scope, forge: forge} do
      {:ok, page} =
        Pages.create(scope, %{"title" => "Bills", "kind" => "database", "space_id" => forge.id})

      %{page: page, collection: Databases.collection(page)}
    end

    test "reminds its people at 09:00 of the day, and the day moved replaces it", %{
      scope: scope,
      hanzo: hanzo,
      masamune: masamune,
      collection: collection
    } do
      day = Date.add(Date.utc_today(), 2)

      {:ok, bill} =
        Box.insert(
          collection,
          %{"Name" => "Electricity", "Due" => day, "Owner" => "user:#{masamune.id}"},
          actor: scope
        )

      Notifications.settle()
      assert [%{status: "scheduled"}] = events(RecordDue)

      {:ok, _} = Box.update(collection, bill.id, %{"Due" => Date.add(day, 7)}, actor: scope)
      Notifications.settle()

      assert ["cancelled", "scheduled"] ==
               events(RecordDue) |> Enum.map(& &1.status) |> Enum.sort()

      run_scheduled(DateTime.add(DateTime.utc_now(), 4, :day))
      refute_notified(RecordDue, to: masamune)

      run_scheduled(DateTime.add(DateTime.utc_now(), 11, :day))

      assert_notified(RecordDue,
        to: masamune,
        data: %{
          "title" => "Electricity",
          "field" => "Due",
          "on" => Date.to_iso8601(Date.add(day, 7))
        }
      )

      refute_notified(RecordDue, to: hanzo)
    end

    test "with no one in it, reminds who made it; done, it reminds no more", %{
      scope: scope,
      hanzo: hanzo,
      collection: collection
    } do
      {:ok, bill} =
        Box.insert(collection, %{"Name" => "Water", "Due" => Date.add(Date.utc_today(), 1)},
          actor: scope
        )

      Notifications.settle()
      {:ok, _} = Box.update(collection, bill.id, %{"Status" => "Done"}, actor: scope)
      Notifications.settle()
      assert ["cancelled"] == events(RecordDue) |> Enum.map(& &1.status)

      run_scheduled(DateTime.add(DateTime.utc_now(), 3, :day))
      refute_notified(RecordDue, to: hanzo)
    end

    test "a day gone by reminds of nothing, and a record deleted cancels its own", %{
      scope: scope,
      collection: collection
    } do
      {:ok, _} =
        Box.insert(collection, %{"Name" => "Old", "Due" => Date.add(Date.utc_today(), -3)},
          actor: scope
        )

      {:ok, later} =
        Box.insert(collection, %{"Name" => "Later", "Due" => Date.add(Date.utc_today(), 3)},
          actor: scope
        )

      Notifications.settle()
      assert [%{status: "scheduled"}] = events(RecordDue)

      {:ok, _} = Box.delete(collection, later.id, actor: scope)
      Notifications.settle()
      assert [%{status: "cancelled"}] = events(RecordDue)
    end

    test "a bill paid that repeats reminds of its next one", %{
      scope: scope,
      hanzo: hanzo,
      collection: collection
    } do
      {:ok, collection} =
        Databases.add_field(scope, collection, %{"name" => "Repeats", "type" => "repeat"})

      {:ok, bill} =
        Box.insert(
          collection,
          %{"Name" => "Rent", "Due" => Date.add(Date.utc_today(), 1), "Repeats" => "FREQ=WEEKLY"},
          actor: scope
        )

      {:ok, _} = Box.update(collection, bill.id, %{"Status" => "Done"}, actor: scope)
      Notifications.settle()

      run_scheduled(DateTime.add(DateTime.utc_now(), 9, :day))

      assert_notified(RecordDue,
        to: hanzo,
        data: %{"title" => "Rent", "on" => Date.to_iso8601(Date.add(Date.utc_today(), 8))}
      )
    end
  end
end
