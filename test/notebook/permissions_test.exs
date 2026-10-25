defmodule Notebook.PermissionsTest do
  # SQLite takes one writer at a time: these write a lot, so they run alone.
  use Notebook.DataCase, async: false

  import Notebook.AccountsFixtures

  alias Notebook.Accounts.Scope
  alias Notebook.{Collaboration, Pages, Spaces}

  setup do
    hanzo = user_fixture(%{name: "Hattori Hanzo"})
    yuki = user_fixture(%{name: "Yuki Hattori"})
    scope = Scope.for_user(hanzo)
    {:ok, forge} = Spaces.create_team(scope, %{name: "The forge"})
    {:ok, _} = Spaces.add_member(scope, forge, yuki, "commenter")

    %{hanzo: hanzo, yuki: yuki, scope: scope, yuki_scope: Scope.for_user(yuki), forge: forge}
  end

  test "a Private page is its owner's alone", %{
    hanzo: hanzo,
    scope: scope,
    yuki_scope: yuki_scope
  } do
    {:ok, letter} =
      Pages.create(scope, %{
        "title" => "Letters I never sent",
        "space_id" => Spaces.private!(hanzo).id
      })

    assert Enum.any?(Pages.list(scope), &(&1.id == letter.id))
    refute Enum.any?(Pages.list(yuki_scope), &(&1.id == letter.id))
    assert Pages.get(yuki_scope, letter.id) == nil

    error = assert_raise Sekisho.Denied, fn -> Pages.get!(yuki_scope, letter.id) end
    assert Plug.Exception.status(error) == 404
  end

  test "a commenter reads and comments, and does not write", %{
    scope: scope,
    yuki_scope: yuki_scope,
    forge: forge
  } do
    {:ok, page} = Pages.create(scope, %{"title" => "The last blade", "space_id" => forge.id})

    assert Pages.allowed?(yuki_scope, :read, page)
    assert Pages.allowed?(yuki_scope, :comment, page)
    refute Pages.allowed?(yuki_scope, :edit, page)
    assert {:error, %Sekisho.Denied{}} = Pages.update(yuki_scope, page, %{"title" => "Mine"})
    assert {:error, %Sekisho.Denied{}} = Pages.archive(yuki_scope, page)

    assert {:error, %Sekisho.Denied{}} =
             Pages.create(yuki_scope, %{"title" => "X", "space_id" => forge.id})
  end

  test "a page moves only between spaces its mover edits", %{
    hanzo: hanzo,
    scope: scope,
    yuki: yuki,
    yuki_scope: yuki_scope,
    forge: forge
  } do
    {:ok, page} =
      Pages.create(scope, %{"title" => "Draft", "space_id" => Spaces.private!(hanzo).id})

    {:ok, plans} = Spaces.create_folder(scope, forge, %{name: "Plans"})

    assert {:ok, moved} = Pages.move(scope, page, forge.id, plans.id)
    assert {moved.space_id, moved.folder_id} == {forge.id, plans.id}

    {:ok, mine} =
      Pages.create(yuki_scope, %{"title" => "Mine", "space_id" => Spaces.private!(yuki).id})

    assert {:error, %Sekisho.Denied{}} = Pages.move(yuki_scope, mine, forge.id)
  end

  test "a folder of another space is refused", %{hanzo: hanzo, scope: scope, forge: forge} do
    {:ok, plans} = Spaces.create_folder(scope, forge, %{name: "Plans"})

    assert {:error, :not_found} =
             Pages.create(scope, %{
               "title" => "Lost",
               "space_id" => Spaces.private!(hanzo).id,
               "folder_id" => plans.id
             })
  end

  test "an archived page leaves the lists and comes back", %{scope: scope, forge: forge} do
    {:ok, page} = Pages.create(scope, %{"title" => "Sword orders, 1998", "space_id" => forge.id})
    {:ok, page} = Pages.archive(scope, page)

    refute Enum.any?(Pages.list(scope), &(&1.id == page.id))
    assert [%{id: id}] = Pages.list(scope, archived: true)
    assert id == page.id

    {:ok, _} = Pages.restore(scope, page)
    assert Enum.any?(Pages.list(scope), &(&1.id == page.id))
  end

  test "a page's room lets in whom its space lets in, as far as their role goes", %{
    hanzo: hanzo,
    yuki: yuki,
    scope: scope,
    forge: forge
  } do
    {:ok, page} = Pages.create(scope, %{"title" => "The last blade", "space_id" => forge.id})
    room = Collaboration.room(page)
    yuki_id = Issho.Identity.new(%{id: to_string(yuki.id), name: yuki.name})

    assert Collaboration.authorize(yuki_id, room, :join) == :ok
    assert Collaboration.authorize(yuki_id, room, :comment) == :ok
    assert Collaboration.authorize(yuki_id, room, :write) == {:error, :forbidden}

    # An agent may do what its person may.
    agent =
      Issho.Identity.new(%{id: "agent:#{yuki.id}", name: "Claude", kind: :agent},
        on_behalf_of: yuki
      )

    assert Collaboration.authorize(agent, room, :read) == :ok
    assert Collaboration.authorize(agent, room, :write) == {:error, :forbidden}

    {:ok, letter} =
      Pages.create(scope, %{"title" => "Letter", "space_id" => Spaces.private!(hanzo).id})

    assert Collaboration.authorize(yuki_id, Collaboration.room(letter), :join) ==
             {:error, :forbidden}
  end

  test "a review slot names only a page its reader may read", %{
    hanzo: hanzo,
    scope: scope,
    yuki_scope: yuki_scope
  } do
    {:ok, _} =
      Pages.create(scope, %{
        "title" => "Secret",
        "space_id" => Spaces.private!(hanzo).id,
        "review_at" => "2027-03-15T11:00:00Z"
      })

    range = Date.range(~D[2027-03-15], ~D[2027-03-15])

    assert %{time: ~T[11:00:00], disabled: true, label: "Taken: Secret"} in Pages.review_slots(
             scope,
             range
           )[~D[2027-03-15]][:slots]

    assert %{time: ~T[11:00:00], disabled: true, label: "Taken"} in Pages.review_slots(
             yuki_scope,
             range
           )[~D[2027-03-15]][:slots]
  end
end
