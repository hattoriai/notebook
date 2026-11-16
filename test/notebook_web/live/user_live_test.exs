defmodule NotebookWeb.UserLiveTest do
  use NotebookWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Notebook.AccountsFixtures

  alias Notebook.Accounts.UserIdentity
  alias Notebook.Invitations

  setup do
    Req.Test.stub(Notebook.OIDC, fn conn ->
      Req.Test.json(conn, %{
        "issuer" => "https://accounts.google.com",
        "authorization_endpoint" => "https://accounts.google.com/o/oauth2/v2/auth",
        "token_endpoint" => "https://oauth2.googleapis.com/token",
        "jwks_uri" => "https://www.googleapis.com/oauth2/v3/certs"
      })
    end)

    admin = user_fixture(%{name: "Admin User", admin: true})
    scope = Notebook.Accounts.Scope.for_user(admin)

    # Save OIDC configuration for testing
    {:ok, _config} =
      Notebook.OIDC.save(scope, %{
        enabled: true,
        name: "Google Workspace",
        issuer: "https://accounts.google.com",
        client_id: "test-client-id",
        client_secret: "test-secret",
        password_login: true,
        auto_register: true
      })

    on_exit(fn ->
      Notebook.OIDC.save(scope, %{
        enabled: false,
        name: "Single Sign-On",
        issuer: "",
        client_id: "",
        client_secret: "",
        password_login: true,
        auto_register: false
      })

      Invitations.set_invite_only(scope, false)
    end)

    %{admin: admin, scope: scope}
  end

  describe "UserLive.Login" do
    test "renders SSO button when OIDC is enabled", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/users/log-in")

      assert html =~ "Log in with Google Workspace"
      assert has_element?(view, "#sso-login")
      assert has_element?(view, "#login_form_password")
    end

    test "hides password form when password_login is disabled", %{conn: conn, scope: scope} do
      {:ok, _} =
        Notebook.OIDC.save(scope, %{
          enabled: true,
          name: "Google Workspace",
          issuer: "https://accounts.google.com",
          client_id: "test-client-id",
          client_secret: "test-secret",
          password_login: false,
          auto_register: true
        })

      {:ok, view, html} = live(conn, ~p"/users/log-in")

      assert html =~ "Log in with Google Workspace"
      assert has_element?(view, "#sso-login")
      refute has_element?(view, "#login_form_password")
    end
  end

  describe "UserLive.Registration" do
    test "renders SSO join button when auto_register is enabled", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/users/register")

      assert html =~ "Join with Google Workspace"
      assert has_element?(view, "#sso-register")
    end

    test "renders SSO join button when invite-only but auto_register is true", %{
      conn: conn,
      scope: scope
    } do
      {:ok, true} = Invitations.set_invite_only(scope, true)

      {:ok, view, html} = live(conn, ~p"/users/register")

      assert html =~ "People with an account on Google Workspace can join directly."
      assert has_element?(view, "#sso-register-auto")
    end
  end

  describe "UserLive.Settings" do
    test "displays linked SSO identities on profile page", %{conn: conn, admin: admin} do
      {:ok, _identity} =
        %UserIdentity{}
        |> UserIdentity.changeset(%{
          user_id: admin.id,
          provider: "oidc",
          issuer: "https://accounts.google.com",
          uid: "google-sub-12345",
          email: "admin@google.com"
        })
        |> Notebook.Repo.insert()

      {:ok, view, html} = live(log_in_user(conn, admin), ~p"/account/settings/profile")

      assert has_element?(view, "#profile-sso")
      assert html =~ "admin@google.com"
      assert html =~ "OIDC"
    end

    test "shows password form on password settings page", %{conn: conn, admin: admin} do
      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/account/settings/password")

      assert has_element?(view, "#password_form")
      assert has_element?(view, "#password_form input[name='user[password]']")
    end
  end
end
