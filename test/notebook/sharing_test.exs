defmodule Notebook.SharingTest do
  # SQLite takes one writer at a time: these write a lot, so they run alone.
  use Notebook.DataCase, async: false

  import Chime.Test
  import Notebook.AccountsFixtures

  alias Notebook.Accounts.Scope
  alias Notebook.Notifications.Shared
  alias Notebook.{Pages, Sharing, Spaces}

  setup do
    hanzo = user_fixture(%{name: "Hattori Hanzo"})
    masamune = user_fixture(%{name: "Okazaki Masamune"})
    yuki = user_fixture(%{name: "Yuki Hattori"})
    scope = Scope.for_user(hanzo)
    {:ok, forge} = Spaces.create_team(scope, %{name: "The forge"})
    {:ok, _} = Spaces.add_member(scope, forge, masamune, "commenter")
    {:ok, plans} = Spaces.create_folder(scope, forge, %{name: "Plans"})

    {:ok, blade} =
      Pages.create(scope, %{
        "title" => "The last blade",
        "space_id" => forge.id,
        "folder_id" => plans.id
      })

    {:ok, letter} = Pages.create(scope, %{"title" => "A letter", "space_id" => forge.id})

    %{
      hanzo: hanzo,
      masamune: masamune,
      yuki: yuki,
      scope: scope,
      forge: forge,
      plans: plans,
      blade: blade,
      letter: letter
    }
  end

  test "a page shared with a person: they read it, as their role, and hear of it", %{
    scope: scope,
    yuki: yuki,
    blade: blade,
    letter: letter
  } do
    yuki_scope = Scope.for_user(yuki)
    refute Pages.allowed?(yuki_scope, :read, blade)

    {:ok, _} = Sharing.share(scope, blade, yuki, "commenter")
    assert Pages.allowed?(yuki_scope, :comment, blade)
    refute Pages.allowed?(yuki_scope, :edit, blade)
    refute Pages.allowed?(yuki_scope, :read, letter)

    assert_notified(Shared, to: yuki, data: %{"page" => "The last blade", "role" => "commenter"})

    assert [
             %{
               title: "Hattori Hanzo shared The last blade with you",
               body: "You can read and comment on it."
             }
           ] =
             feed(yuki)

    assert ["The last blade"] == Enum.map(Sharing.shared_with(yuki_scope), & &1.title)
    assert {:ok, %{people: [%{role: "commenter"}], link: nil}} = Sharing.access(scope, blade)

    {:ok, _} = Sharing.share(scope, blade, yuki, "editor")
    assert Pages.allowed?(yuki_scope, :edit, blade)
    assert {:ok, %{people: [%{role: "editor"}]}} = Sharing.access(scope, blade)

    :ok = Sharing.unshare(scope, blade, yuki)
    refute Pages.allowed?(yuki_scope, :read, blade)
    assert Sharing.shared_with(yuki_scope) == []
  end

  test "a folder shared shares its pages", %{
    scope: scope,
    yuki: yuki,
    plans: plans,
    blade: blade,
    letter: letter
  } do
    {:ok, _} = Sharing.share(scope, plans, yuki, "viewer")
    yuki_scope = Scope.for_user(yuki)

    assert Pages.allowed?(yuki_scope, :read, blade)
    refute Pages.allowed?(yuki_scope, :comment, blade)
    refute Pages.allowed?(yuki_scope, :read, letter)
    assert_notified(Shared, to: yuki, data: %{"folder" => "Plans"})
  end

  test "a link shares a page with anyone who has it, until it is taken back", %{
    scope: scope,
    yuki: yuki,
    blade: blade
  } do
    {:ok, token} = Sharing.link(scope, blade, "viewer")
    assert Sharing.url(blade, token) =~ "/pages/#{blade.id}?key=#{token}"

    without = Scope.for_user(yuki)
    with_link = Scope.with_links(without, [token])
    refute Pages.allowed?(without, :read, blade)
    assert Pages.allowed?(with_link, :read, blade)
    refute Pages.allowed?(with_link, :comment, blade)
    assert {:ok, %{link: "viewer"}} = Sharing.access(scope, blade)

    # A new link takes back the last one.
    {:ok, new} = Sharing.link(scope, blade, "commenter")
    refute Pages.allowed?(with_link, :read, blade)
    assert Pages.allowed?(Scope.with_links(without, [new]), :comment, blade)

    :ok = Sharing.unlink(scope, blade)
    refute Pages.allowed?(Scope.with_links(without, [new]), :read, blade)
  end

  test "a link gives a page no more than commenting, and a folder no more than reading", %{
    scope: scope,
    blade: blade,
    plans: plans
  } do
    assert {:error, :role} = Sharing.link(scope, blade, "editor")
    assert {:error, :role} = Sharing.link(scope, plans, "commenter")
  end

  test "its editors share it, and no one gives more than they have", %{
    masamune: masamune,
    yuki: yuki,
    blade: blade
  } do
    masamune_scope = Scope.for_user(masamune)
    refute Sharing.can_share?(masamune_scope, blade)
    assert {:error, _} = Sharing.share(masamune_scope, blade, yuki, "viewer")
    assert {:error, _} = Sharing.link(masamune_scope, blade, "viewer")
  end
end
