defmodule Notebook.SpacesTest do
  # SQLite takes one writer at a time: these write a lot, so they run alone.
  use Notebook.DataCase, async: false

  import Notebook.AccountsFixtures

  alias Notebook.Accounts.Scope
  alias Notebook.{Pages, Spaces}
  alias Notebook.Spaces.Space

  setup do
    hanzo = user_fixture(%{name: "Hattori Hanzo"})
    yuki = user_fixture(%{name: "Yuki Hattori"})
    %{hanzo: hanzo, yuki: yuki, scope: Scope.for_user(hanzo), yuki_scope: Scope.for_user(yuki)}
  end

  test "every account is in General, with a Private space of its own", %{
    hanzo: hanzo,
    scope: scope
  } do
    assert [%Space{kind: "general"}, %Space{kind: "private", owner_id: owner}] =
             Spaces.list(scope)

    assert owner == hanzo.id
    assert {:ok, _} = Spaces.welcome(hanzo)
    assert length(Spaces.list(scope)) == 2
  end

  test "a team space has its maker as admin, and only its members see it", %{
    scope: scope,
    yuki: yuki,
    yuki_scope: yuki_scope
  } do
    {:ok, forge} = Spaces.create_team(scope, %{name: "The forge"})
    assert [%{role: "admin"}] = Spaces.members(forge)
    refute Enum.any?(Spaces.list(yuki_scope), &(&1.id == forge.id))

    {:ok, _} = Spaces.add_member(scope, forge, yuki, "commenter")
    assert Enum.any?(Spaces.list(yuki_scope), &(&1.id == forge.id))
    assert Spaces.allowed?(yuki_scope, :comment, forge)
    refute Spaces.allowed?(yuki_scope, :edit, forge)
  end

  test "only a space's admins manage its members, and it keeps one admin", %{
    scope: scope,
    hanzo: hanzo,
    yuki: yuki,
    yuki_scope: yuki_scope
  } do
    {:ok, forge} = Spaces.create_team(scope, %{name: "The forge"})
    {:ok, member} = Spaces.add_member(scope, forge, yuki, "editor")

    assert {:error, %Sekisho.Denied{}} = Spaces.add_member(yuki_scope, forge, hanzo, "viewer")
    assert {:error, %Sekisho.Denied{}} = Spaces.set_role(yuki_scope, member, "admin")

    [admin] = Enum.filter(Spaces.members(forge), &(&1.role == "admin"))
    assert {:error, :last_admin} = Spaces.set_role(scope, admin, "editor")
    assert {:error, :last_admin} = Spaces.remove_member(scope, admin)

    {:ok, _} = Spaces.set_role(scope, member, "admin")
    assert {:ok, _} = Spaces.set_role(scope, admin, "editor")
  end

  test "General and Private spaces keep their names and their people", %{
    scope: scope,
    hanzo: hanzo,
    yuki: yuki
  } do
    assert {:error, :fixed} = Spaces.update(scope, Spaces.private!(hanzo), %{name: "Mine"})
    assert {:error, :fixed} = Spaces.add_member(scope, Spaces.private!(hanzo), yuki, "viewer")
  end

  test "folders are two levels deep at most, and an editor makes them", %{
    scope: scope,
    yuki_scope: yuki_scope
  } do
    {:ok, forge} = Spaces.create_team(scope, %{name: "The forge"})
    {:ok, plans} = Spaces.create_folder(scope, forge, %{name: "Plans"})
    {:ok, ceremonies} = Spaces.create_folder(scope, forge, %{name: "Ceremonies"}, plans)
    assert {:error, :too_deep} = Spaces.create_folder(scope, forge, %{name: "Deeper"}, ceremonies)
    assert {:error, %Sekisho.Denied{}} = Spaces.create_folder(yuki_scope, forge, %{name: "Mine"})
  end

  test "deleting a folder keeps its pages, at the top of the space", %{scope: scope} do
    {:ok, forge} = Spaces.create_team(scope, %{name: "The forge"})
    {:ok, plans} = Spaces.create_folder(scope, forge, %{name: "Plans"})
    {:ok, inner} = Spaces.create_folder(scope, forge, %{name: "Inner"}, plans)

    {:ok, page} =
      Pages.create(scope, %{
        "title" => "The last blade",
        "space_id" => forge.id,
        "folder_id" => inner.id
      })

    {:ok, _} = Spaces.delete_folder(scope, plans)
    assert %{folder_id: nil, space_id: space_id} = Pages.get!(scope, page.id)
    assert space_id == forge.id
  end

  test "the tree has the spaces, their folders and their pages, not the archived ones", %{
    scope: scope
  } do
    {:ok, forge} = Spaces.create_team(scope, %{name: "The forge"})
    {:ok, plans} = Spaces.create_folder(scope, forge, %{name: "Plans"})

    {:ok, _} =
      Pages.create(scope, %{"title" => "Plan", "space_id" => forge.id, "folder_id" => plans.id})

    {:ok, loose} = Pages.create(scope, %{"title" => "Loose", "space_id" => forge.id})
    {:ok, old} = Pages.create(scope, %{"title" => "Old", "space_id" => forge.id})
    {:ok, _} = Pages.archive(scope, old)

    node = Enum.find(Spaces.tree(scope), &(&1.space.id == forge.id))
    assert [%{folder: %{name: "Plans"}, pages: [%{title: "Plan"}]}] = node.folders
    assert [%{id: id}] = node.pages
    assert id == loose.id
  end

  test "a space's tree keeps the order people leave it in, new pages last", %{scope: scope} do
    {:ok, forge} = Spaces.create_team(scope, %{name: "The forge"})
    {:ok, plans} = Spaces.create_folder(scope, forge, %{name: "Plans"})
    {:ok, a} = Pages.create(scope, %{"title" => "Zebra", "space_id" => forge.id})
    {:ok, b} = Pages.create(scope, %{"title" => "Apple", "space_id" => forge.id})

    titles = fn ->
      node = Enum.find(Spaces.tree(scope), &(&1.space.id == forge.id))

      for item <- node.items,
          is_nil(item.parent_id),
          do: Map.get(item.record, :title) || item.record.name
    end

    assert titles.() == ["Plans", "Zebra", "Apple"]

    {:ok, _} =
      Spaces.move(scope, forge, %Narabe.Move{
        ids: ["page:#{b.id}"],
        parent: nil,
        before: "folder:#{plans.id}"
      })

    assert titles.() == ["Apple", "Plans", "Zebra"]

    {:ok, _} = Pages.move(scope, a, forge.id, plans.id)

    {:ok, c} =
      Pages.create(scope, %{"title" => "Middle", "space_id" => forge.id, "folder_id" => plans.id})

    node = Enum.find(Spaces.tree(scope), &(&1.space.id == forge.id))
    assert [%{folder: %{name: "Plans"}, pages: [%{id: first}, %{id: last}]}] = node.folders
    assert {first, last} == {a.id, c.id}
  end

  test "a move in a space's tree keeps folders two levels deep, and is its editors'", %{
    scope: scope,
    yuki: yuki,
    yuki_scope: yuki_scope
  } do
    {:ok, forge} = Spaces.create_team(scope, %{name: "The forge"})
    {:ok, _} = Spaces.add_member(scope, forge, yuki, "commenter")
    {:ok, plans} = Spaces.create_folder(scope, forge, %{name: "Plans"})
    {:ok, inner} = Spaces.create_folder(scope, forge, %{name: "Inner"}, plans)
    {:ok, other} = Spaces.create_folder(scope, forge, %{name: "Other"})
    {:ok, page} = Pages.create(scope, %{"title" => "A page", "space_id" => forge.id})

    move = fn scope, id, parent ->
      Spaces.move(scope, forge, %Narabe.Move{ids: [id], parent: parent})
    end

    # A folder that holds folders stays at the top; a folder in a folder holds no folder.
    assert {:error, :too_deep} = move.(scope, "folder:#{plans.id}", "folder:#{other.id}")
    assert {:error, :too_deep} = move.(scope, "folder:#{other.id}", "folder:#{inner.id}")
    assert {:ok, _} = move.(scope, "folder:#{other.id}", "folder:#{plans.id}")
    # A page holds nothing.
    assert {:error, :not_accepted} = move.(scope, "folder:#{inner.id}", "page:#{page.id}")

    assert {:error, %Sekisho.Denied{}} =
             move.(yuki_scope, "page:#{page.id}", "folder:#{plans.id}")
  end

  test "a change to the tree tells its subscribers", %{scope: scope} do
    Spaces.subscribe_tree()
    {:ok, _forge} = Spaces.create_team(scope, %{name: "The forge"})
    assert_receive :tree_changed
  end
end
