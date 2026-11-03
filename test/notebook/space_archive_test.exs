defmodule Notebook.SpaceArchiveTest do
  # SQLite takes one writer at a time: these write a lot, so they run alone.
  use Notebook.DataCase, async: false

  import Notebook.AccountsFixtures

  alias Notebook.Accounts.Scope
  alias Notebook.{Pages, Repo, Search, Sharing, Spaces}
  alias Notebook.Spaces.Space

  setup do
    hanzo = user_fixture(%{name: "Hattori Hanzo"})
    yuki = user_fixture(%{name: "Yuki Hattori"})
    admin = user_fixture(%{name: "Okazaki Masamune", admin: true})
    scope = Scope.for_user(hanzo)
    {:ok, forge} = Spaces.create_team(scope, %{name: "The forge"})
    {:ok, _} = Spaces.add_member(scope, forge, yuki, "editor")
    {:ok, blade} = Pages.create(scope, %{"title" => "The last blade", "space_id" => forge.id})

    %{
      scope: scope,
      yuki: yuki,
      yuki_scope: Scope.for_user(yuki),
      admin_scope: Scope.for_user(admin),
      forge: forge,
      blade: blade
    }
  end

  describe "icons" do
    test "one of the notebook's, an emoji, or its kind's again", %{scope: scope, forge: forge} do
      assert {:ok, %Space{icon: "hero-fire"}} = Spaces.set_icon(scope, forge, "hero-fire")
      assert {:ok, %Space{icon: "🔥"} = forge} = Spaces.set_icon(scope, forge, "🔥")
      assert {:ok, %Space{icon: nil}} = Spaces.set_icon(scope, forge, "")
    end

    test "nothing else, and only its admins", %{scope: scope, yuki_scope: yuki, forge: forge} do
      assert {:error, %Ecto.Changeset{}} = Spaces.set_icon(scope, forge, "hero-not-ours")
      assert {:error, %Ecto.Changeset{}} = Spaces.set_icon(scope, forge, "a")
      assert {:error, %Ecto.Changeset{}} = Spaces.set_icon(scope, forge, "image:javascript:x")
      assert {:error, _} = Spaces.set_icon(yuki, forge, "🔥")
    end
  end

  describe "the Archive" do
    test "a space and its pages leave everyone's lists, and come back", %{
      scope: scope,
      yuki_scope: yuki,
      forge: forge,
      blade: blade
    } do
      {:ok, forge} = Spaces.archive(scope, forge)

      for s <- [scope, yuki] do
        refute Enum.any?(Spaces.list(s), &(&1.id == forge.id))
        refute Enum.any?(Pages.list(s), &(&1.id == blade.id))
        assert Search.search(s, "blade") |> Enum.empty?()
        assert_raise Sekisho.Denied, fn -> Pages.get!(s, blade.id) end
      end

      # Its admin finds it in the Archive; its editor does not.
      assert [%Space{id: id}] = Spaces.archived(scope)
      assert id == forge.id
      assert Spaces.archived(yuki) == []

      {:ok, _} = Spaces.restore(scope, forge)
      assert Enum.any?(Spaces.list(yuki), &(&1.id == forge.id))
      assert Pages.get!(yuki, blade.id)
    end

    test "its admins and the notebook's may; not its editors, nor General", %{
      scope: scope,
      yuki_scope: yuki,
      admin_scope: admin,
      forge: forge
    } do
      assert {:error, _} = Spaces.archive(yuki, forge)
      assert {:error, :fixed} = Spaces.archive(scope, Spaces.general!())
      assert {:ok, forge} = Spaces.archive(admin, forge)
      assert [_] = Spaces.archived(admin)
      assert {:ok, _} = Spaces.restore(admin, forge)
    end

    test "deleted for good from the Archive, with all that is its pages'", %{
      scope: scope,
      yuki: yuki,
      forge: forge,
      blade: blade
    } do
      {:ok, _} = Sharing.share(scope, blade, yuki, "commenter")

      Repo.insert_all("issho_documents", [
        %{
          id: "page:#{blade.id}/issho.comments",
          epoch: "e",
          revision: 1,
          document: "{}",
          content: "{}"
        }
      ])

      # Only from the Archive.
      assert {:error, :not_archived} = Spaces.delete(scope, forge)
      {:ok, forge} = Spaces.archive(scope, forge)
      assert {:ok, _} = Spaces.delete(scope, forge)

      refute Repo.get(Space, forge.id)
      refute Repo.get(Notebook.Pages.Page, blade.id)
      assert Spaces.archived(scope) == []

      import Ecto.Query

      assert Repo.aggregate(
               from(d in "issho_documents", where: like(d.id, ^"page:#{blade.id}%")),
               :count
             ) == 0

      assert Repo.aggregate(
               from(g in "sekisho_grants",
                 where: g.resource_type == "pages" and g.resource_id == ^blade.id
               ),
               :count
             ) == 0
    end
  end
end
