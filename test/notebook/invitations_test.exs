defmodule Notebook.InvitationsTest do
  use Notebook.DataCase, async: true

  import Notebook.AccountsFixtures

  alias Notebook.Accounts.{Scope, User}
  alias Notebook.Invitations
  alias Notebook.Invitations.Invitation

  defp attrs(email), do: %{name: "Yuki Hattori", email: email, password: "a long password!"}

  test "the notebook's first person registers, and is its admin, even invite only" do
    Repo.insert!(%Notebook.Storage.Setting{key: "registration", value: %{"invite_only" => true}})

    assert {:ok, %User{admin: true}} = Invitations.register(attrs("first@example.com"))
    assert {:error, :invite_only} = Invitations.register(attrs("second@example.com"))
  end

  describe "an invite-only notebook" do
    setup do
      admin = user_fixture(%{name: "Hattori Hanzo", admin: true})
      scope = Scope.for_user(admin)
      {:ok, true} = Invitations.set_invite_only(scope, true)
      %{scope: scope}
    end

    test "takes no one without a link", %{scope: _scope} do
      refute Invitations.open?()
      refute Invitations.open?("not-a-token")
      assert {:error, :invite_only} = Invitations.register(attrs("yuki@example.com"))
      assert {:error, :invite_only} = Invitations.register(attrs("yuki@example.com"), "nope")
    end

    test "takes a person with a link, once", %{scope: scope} do
      {:ok, invitation, token} = Invitations.create(scope)
      assert Invitations.open?(token)

      assert {:ok, %User{admin: false} = yuki} =
               Invitations.register(attrs("yuki@example.com"), token)

      assert %Invitation{used_by_id: id, used_at: %DateTime{}} = Repo.reload(invitation)
      assert id == yuki.id
      refute Invitations.open?(token)
      assert {:error, :invite_only} = Invitations.register(attrs("kenji@example.com"), token)
      assert Invitations.pending() == []
    end

    test "a link expires", %{scope: scope} do
      {:ok, invitation, token} = Invitations.create(scope)

      invitation
      |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(:second), -1, :second))
      |> Repo.update!()

      refute Invitations.open?(token)
    end

    test "a link not used is taken back", %{scope: scope} do
      {:ok, invitation, token} = Invitations.create(scope)
      assert [%Invitation{}] = Invitations.pending()

      assert {:ok, _} = Invitations.revoke(scope, invitation.id)
      refute Invitations.open?(token)
    end

    test "a failed registration keeps the link", %{scope: scope} do
      {:ok, _invitation, token} = Invitations.create(scope)

      assert {:error, %Ecto.Changeset{}} =
               Invitations.register(%{name: "Y", email: "bad", password: "x"}, token)

      assert Invitations.open?(token)
    end
  end

  test "only an admin invites, or closes the notebook" do
    user_fixture(%{admin: true})
    scope = Scope.for_user(user_fixture())

    assert {:error, :forbidden} = Invitations.set_invite_only(scope, true)
    assert {:error, :forbidden} = Invitations.create(scope)
    refute Invitations.invite_only?()
  end

  test "an open notebook takes anyone" do
    user_fixture(%{admin: true})
    assert Invitations.open?()
    assert {:ok, %User{admin: false}} = Invitations.register(attrs("yuki@example.com"))
  end
end
