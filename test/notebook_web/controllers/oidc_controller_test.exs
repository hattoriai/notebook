defmodule NotebookWeb.OIDCControllerTest do
  use NotebookWeb.ConnCase, async: false

  alias Notebook.Accounts
  alias Notebook.Accounts.Scope
  alias Notebook.Invitations
  alias Notebook.OIDC
  alias Notebook.Repo

  import Notebook.AccountsFixtures

  setup do
    admin = user_fixture(%{name: "Admin User", admin: true})
    scope = Scope.for_user(admin)

    private_key = :public_key.generate_key({:rsa, 2048, 65537})
    {:RSAPrivateKey, _, n_int, e_int, _, _, _, _, _, _, _} = private_key

    n_b64 = :binary.encode_unsigned(n_int) |> Base.url_encode64(padding: false)
    e_b64 = :binary.encode_unsigned(e_int) |> Base.url_encode64(padding: false)

    jwks = [
      %{
        "kty" => "RSA",
        "kid" => "key-1",
        "use" => "sig",
        "alg" => "RS256",
        "n" => n_b64,
        "e" => e_b64
      }
    ]

    sign_jwt = fn payload ->
      header = %{"alg" => "RS256", "kid" => "key-1", "typ" => "JWT"}
      header_b64 = Jason.encode!(header) |> Base.url_encode64(padding: false)
      payload_b64 = Jason.encode!(payload) |> Base.url_encode64(padding: false)
      signed_data = header_b64 <> "." <> payload_b64

      sig =
        :public_key.sign(signed_data, :sha256, private_key) |> Base.url_encode64(padding: false)

      signed_data <> "." <> sig
    end

    enable_oidc = fn attrs ->
      default_attrs = %{
        "enabled" => "true",
        "name" => "Okta",
        "issuer" => "https://auth.example.com",
        "client_id" => "client-123",
        "client_secret" => "secret-xyz",
        "auto_register" => "false",
        "password_login" => "true"
      }

      {:ok, _} = OIDC.save(scope, Map.merge(default_attrs, attrs))
    end

    Req.Test.stub(Notebook.OIDC, fn conn ->
      case conn.request_path do
        "/.well-known/openid-configuration" ->
          Req.Test.json(conn, %{
            "issuer" => "https://auth.example.com",
            "authorization_endpoint" => "https://auth.example.com/oauth/authorize",
            "token_endpoint" => "https://auth.example.com/oauth/token",
            "jwks_uri" => "https://auth.example.com/oauth/jwks"
          })

        "/oauth/jwks" ->
          Req.Test.json(conn, %{"keys" => jwks})

        _ ->
          Plug.Conn.send_resp(conn, 404, "Not Found")
      end
    end)

    %{
      scope: scope,
      admin: admin,
      jwks: jwks,
      sign_jwt: sign_jwt,
      enable_oidc: enable_oidc
    }
  end

  describe "GET /users/oidc" do
    test "redirects to log-in when OIDC is disabled", %{conn: conn} do
      conn = get(conn, ~p"/users/oidc")
      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Single Sign-On is not enabled"
    end

    test "redirects to provider authorization URL with PKCE parameters", %{
      conn: conn,
      enable_oidc: enable_oidc
    } do
      enable_oidc.(%{})

      conn = get(conn, ~p"/users/oidc")
      assert target = redirected_to(conn, 302)
      assert target =~ "https://auth.example.com/oauth/authorize?"
      assert target =~ "client_id=client-123"
      assert target =~ "response_type=code"
      assert target =~ "code_challenge="
      assert target =~ "code_challenge_method=S256"

      assert state = get_session(conn, :oidc_state)
      assert is_binary(state) and state != ""
      assert nonce = get_session(conn, :oidc_nonce)
      assert is_binary(nonce) and nonce != ""
      assert verifier = get_session(conn, :oidc_code_verifier)
      assert is_binary(verifier) and verifier != ""
    end

    test "saves invite token in session when passed", %{conn: conn, enable_oidc: enable_oidc} do
      enable_oidc.(%{})

      conn = get(conn, ~p"/users/oidc?invite=secret-invite-token")
      assert redirected_to(conn, 302)
      assert get_session(conn, :oidc_invite) == "secret-invite-token"
    end
  end

  describe "GET /users/oidc/callback" do
    test "rejects callback with state mismatch", %{conn: conn, enable_oidc: enable_oidc} do
      enable_oidc.(%{})

      conn =
        conn
        |> init_test_session(%{oidc_state: "expected-state"})
        |> get(~p"/users/oidc/callback?code=some-code&state=wrong-state")

      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Invalid sign-in state"
    end

    test "handles provider error response gracefully", %{conn: conn, enable_oidc: enable_oidc} do
      enable_oidc.(%{})

      conn =
        conn
        |> init_test_session(%{oidc_state: "my-state"})
        |> get(~p"/users/oidc/callback?error=access_denied&error_description=User+declined")

      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "User declined"
      refute get_session(conn, :oidc_state)
    end

    test "logs in existing user and links identity", %{
      conn: conn,
      enable_oidc: enable_oidc,
      sign_jwt: sign_jwt,
      jwks: jwks
    } do
      enable_oidc.(%{})
      existing = user_fixture(%{email: "matsu@example.com", name: "Matsu"})

      token_payload = %{
        "iss" => "https://auth.example.com",
        "sub" => "matsu-sub-123",
        "aud" => "client-123",
        "exp" => System.system_time(:second) + 3600,
        "nonce" => "valid-nonce",
        "email" => "matsu@example.com",
        "email_verified" => true,
        "name" => "Matsu External"
      }

      id_token = sign_jwt.(token_payload)

      Req.Test.stub(Notebook.OIDC, fn
        %{request_path: "/.well-known/openid-configuration"} = conn ->
          Req.Test.json(conn, %{
            "issuer" => "https://auth.example.com",
            "authorization_endpoint" => "https://auth.example.com/oauth/authorize",
            "token_endpoint" => "https://auth.example.com/oauth/token",
            "jwks_uri" => "https://auth.example.com/oauth/jwks"
          })

        %{request_path: "/oauth/jwks"} = conn ->
          Req.Test.json(conn, %{"keys" => jwks})

        %{request_path: "/oauth/token"} = conn ->
          Req.Test.json(conn, %{
            "access_token" => "access-token-1",
            "id_token" => id_token,
            "token_type" => "Bearer"
          })
      end)

      conn =
        conn
        |> init_test_session(%{
          oidc_state: "valid-state",
          oidc_nonce: "valid-nonce",
          oidc_code_verifier: "my-verifier"
        })
        |> get(~p"/users/oidc/callback?code=good-code&state=valid-state")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Welcome, Matsu"
      assert get_session(conn, :user_token)

      # Verify identity was linked in DB
      identities = Accounts.get_user_identities(existing)
      assert length(identities) == 1
      assert hd(identities).uid == "matsu-sub-123"
    end

    test "provisions new user when registration is open and creates their spaces", %{
      conn: conn,
      enable_oidc: enable_oidc,
      sign_jwt: sign_jwt,
      jwks: jwks
    } do
      enable_oidc.(%{})

      token_payload = %{
        "iss" => "https://auth.example.com",
        "sub" => "new-user-sub-456",
        "aud" => "client-123",
        "exp" => System.system_time(:second) + 3600,
        "nonce" => "new-nonce",
        "email" => "newbie@example.com",
        "email_verified" => true,
        "name" => "New Contributor"
      }

      id_token = sign_jwt.(token_payload)

      Req.Test.stub(Notebook.OIDC, fn
        %{request_path: "/.well-known/openid-configuration"} = conn ->
          Req.Test.json(conn, %{
            "issuer" => "https://auth.example.com",
            "authorization_endpoint" => "https://auth.example.com/oauth/authorize",
            "token_endpoint" => "https://auth.example.com/oauth/token",
            "jwks_uri" => "https://auth.example.com/oauth/jwks"
          })

        %{request_path: "/oauth/jwks"} = conn ->
          Req.Test.json(conn, %{"keys" => jwks})

        %{request_path: "/oauth/token"} = conn ->
          Req.Test.json(conn, %{
            "access_token" => "access-token-2",
            "id_token" => id_token,
            "token_type" => "Bearer"
          })
      end)

      conn =
        conn
        |> init_test_session(%{
          oidc_state: "state-xyz",
          oidc_nonce: "new-nonce",
          oidc_code_verifier: "my-verifier"
        })
        |> get(~p"/users/oidc/callback?code=good-code&state=state-xyz")

      assert redirected_to(conn) == ~p"/"
      assert user = Accounts.get_user_by_email("newbie@example.com")
      assert user.name == "New Contributor"
      assert user.confirmed_at
      refute user.admin

      # Spaces are created: General and Private
      spaces = Notebook.Spaces.list(Scope.for_user(user))
      assert Enum.any?(spaces, &(&1.kind == "general"))
      assert Enum.any?(spaces, &(&1.kind == "private"))
    end

    test "rejects unverified email", %{
      conn: conn,
      enable_oidc: enable_oidc,
      sign_jwt: sign_jwt,
      jwks: jwks
    } do
      enable_oidc.(%{})

      token_payload = %{
        "iss" => "https://auth.example.com",
        "sub" => "unverified-sub",
        "aud" => "client-123",
        "exp" => System.system_time(:second) + 3600,
        "nonce" => "unverified-nonce",
        "email" => "unverified@example.com",
        "email_verified" => false,
        "name" => "Unverified Person"
      }

      id_token = sign_jwt.(token_payload)

      Req.Test.stub(Notebook.OIDC, fn
        %{request_path: "/.well-known/openid-configuration"} = conn ->
          Req.Test.json(conn, %{
            "issuer" => "https://auth.example.com",
            "authorization_endpoint" => "https://auth.example.com/oauth/authorize",
            "token_endpoint" => "https://auth.example.com/oauth/token",
            "jwks_uri" => "https://auth.example.com/oauth/jwks"
          })

        %{request_path: "/oauth/jwks"} = conn ->
          Req.Test.json(conn, %{"keys" => jwks})

        %{request_path: "/oauth/token"} = conn ->
          Req.Test.json(conn, %{"id_token" => id_token})
      end)

      conn =
        conn
        |> init_test_session(%{
          oidc_state: "state-unverified",
          oidc_nonce: "unverified-nonce",
          oidc_code_verifier: "verifier"
        })
        |> get(~p"/users/oidc/callback?code=c&state=state-unverified")

      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "must be verified"
      refute Accounts.get_user_by_email("unverified@example.com")
    end

    test "rejects email when domain is not in allowed_domains", %{
      conn: conn,
      enable_oidc: enable_oidc,
      sign_jwt: sign_jwt,
      jwks: jwks
    } do
      enable_oidc.(%{"allowed_domains" => "corp.example.com"})

      token_payload = %{
        "iss" => "https://auth.example.com",
        "sub" => "sub-outsider",
        "aud" => "client-123",
        "exp" => System.system_time(:second) + 3600,
        "nonce" => "nonce-outsider",
        "email" => "hacker@evil.com",
        "email_verified" => true,
        "name" => "Outsider"
      }

      id_token = sign_jwt.(token_payload)

      Req.Test.stub(Notebook.OIDC, fn
        %{request_path: "/.well-known/openid-configuration"} = conn ->
          Req.Test.json(conn, %{
            "issuer" => "https://auth.example.com",
            "authorization_endpoint" => "https://auth.example.com/oauth/authorize",
            "token_endpoint" => "https://auth.example.com/oauth/token",
            "jwks_uri" => "https://auth.example.com/oauth/jwks"
          })

        %{request_path: "/oauth/jwks"} = conn ->
          Req.Test.json(conn, %{"keys" => jwks})

        %{request_path: "/oauth/token"} = conn ->
          Req.Test.json(conn, %{"id_token" => id_token})
      end)

      conn =
        conn
        |> init_test_session(%{
          oidc_state: "state-outsider",
          oidc_nonce: "nonce-outsider",
          oidc_code_verifier: "verifier"
        })
        |> get(~p"/users/oidc/callback?code=c&state=state-outsider")

      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "domain is not permitted"
    end

    test "respects invite-only instances unless invite token or auto_register", %{
      conn: conn,
      scope: scope,
      enable_oidc: enable_oidc,
      sign_jwt: sign_jwt,
      jwks: jwks
    } do
      enable_oidc.(%{"auto_register" => "false"})
      {:ok, true} = Invitations.set_invite_only(scope, true)

      token_payload = %{
        "iss" => "https://auth.example.com",
        "sub" => "sub-invite-check",
        "aud" => "client-123",
        "exp" => System.system_time(:second) + 3600,
        "nonce" => "nonce-invite",
        "email" => "guest@example.com",
        "email_verified" => true,
        "name" => "Guest"
      }

      id_token = sign_jwt.(token_payload)

      Req.Test.stub(Notebook.OIDC, fn
        %{request_path: "/.well-known/openid-configuration"} = conn ->
          Req.Test.json(conn, %{
            "issuer" => "https://auth.example.com",
            "authorization_endpoint" => "https://auth.example.com/oauth/authorize",
            "token_endpoint" => "https://auth.example.com/oauth/token",
            "jwks_uri" => "https://auth.example.com/oauth/jwks"
          })

        %{request_path: "/oauth/jwks"} = conn ->
          Req.Test.json(conn, %{"keys" => jwks})

        %{request_path: "/oauth/token"} = conn ->
          Req.Test.json(conn, %{"id_token" => id_token})
      end)

      # 1. Uninvited user is rejected
      conn1 =
        conn
        |> init_test_session(%{
          oidc_state: "state-1",
          oidc_nonce: "nonce-invite",
          oidc_code_verifier: "v1"
        })
        |> get(~p"/users/oidc/callback?code=c&state=state-1")

      assert redirected_to(conn1) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn1.assigns.flash, :error) =~ "invite only"

      # 2. User with invitation token succeeds and invitation is marked used
      {:ok, invitation, invite_token} = Invitations.create(scope)

      conn2 =
        conn
        |> init_test_session(%{
          oidc_state: "state-2",
          oidc_nonce: "nonce-invite",
          oidc_code_verifier: "v2",
          oidc_invite: invite_token
        })
        |> get(~p"/users/oidc/callback?code=c&state=state-2")

      assert redirected_to(conn2) == ~p"/"
      assert user = Accounts.get_user_by_email("guest@example.com")
      assert Repo.reload!(invitation).used_by_id == user.id
    end
  end
end
