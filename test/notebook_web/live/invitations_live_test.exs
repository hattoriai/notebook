defmodule NotebookWeb.InvitationsLiveTest do
  use NotebookWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Notebook.AccountsFixtures

  alias Notebook.Accounts.Scope
  alias Notebook.Invitations

  setup do
    %{admin: user_fixture(%{name: "Hattori Hanzo", admin: true})}
  end

  defp close(admin), do: {:ok, true} = Invitations.set_invite_only(Scope.for_user(admin), true)

  defp user_params(email),
    do: %{"name" => "Yuki Hattori", "email" => email, "password" => "a long password!"}

  test "an admin makes the notebook invite only, and makes a link", %{conn: conn, admin: admin} do
    {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/notebook/settings/people")
    refute has_element?(view, "#invite-button")

    view |> element("#joining-form") |> render_change(%{"joining" => "invite"})
    assert Invitations.invite_only?()

    view |> element("#invite-button") |> render_click()
    assert has_element?(view, "#invite-url")
    assert [invitation] = Invitations.pending()
    assert has_element?(view, "#invitation-#{invitation.id}")

    view |> element("#invitation-#{invitation.id} button") |> render_click()
    assert Invitations.pending() == []
  end

  test "invite only, the Register page says so, and takes no one", %{conn: conn, admin: admin} do
    close(admin)

    {:ok, view, _html} = live(conn, ~p"/users/register")
    assert has_element?(view, "#invite-only")
    refute has_element?(view, "#registration_form")

    conn = post(conn, ~p"/users/register", %{"user" => user_params("yuki@example.com")})
    assert redirected_to(conn) == ~p"/users/register"
    refute Notebook.Accounts.get_user_by_email("yuki@example.com")
  end

  test "invite only, a link opens the Register page, and the account", %{
    conn: conn,
    admin: admin
  } do
    close(admin)
    {:ok, _invitation, token} = Invitations.create(Scope.for_user(admin))

    {:ok, view, _html} = live(conn, ~p"/users/register?#{[invite: token]}")
    assert has_element?(view, "#registration_form input[name=invite]")

    conn =
      post(conn, ~p"/users/register", %{
        "user" => user_params("yuki@example.com"),
        "invite" => token
      })

    assert redirected_to(conn) == ~p"/"
    assert Notebook.Accounts.get_user_by_email("yuki@example.com")
  end
end
