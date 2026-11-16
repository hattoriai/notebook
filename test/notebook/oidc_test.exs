defmodule Notebook.OIDCTest do
  use Notebook.DataCase, async: true

  alias Notebook.Accounts.Scope
  alias Notebook.OIDC
  alias Notebook.OIDC.Config

  import Notebook.AccountsFixtures

  setup do
    admin = user_fixture(%{admin: true})
    %{scope: Scope.for_user(admin), admin: admin}
  end

  describe "config and changeset" do
    test "defaults are reasonable" do
      cfg = %Config{}
      assert cfg.enabled == false
      assert cfg.name == "Single Sign-On"
      assert cfg.password_login == true
      assert cfg.auto_register == false
    end

    test "validates required fields when enabled" do
      changeset = OIDC.change(%Config{}, %{"enabled" => "true"})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).client_id
      assert "can't be blank" in errors_on(changeset).issuer
      assert "is needed for OpenID Connect" in errors_on(changeset).client_secret
    end

    test "validates issuer URL format" do
      changeset =
        OIDC.change(%Config{}, %{
          "enabled" => "true",
          "name" => "Okta",
          "issuer" => "not-a-url",
          "client_id" => "123",
          "client_secret" => "secret"
        })

      refute changeset.valid?
      assert "must be an address starting with https://" in errors_on(changeset).issuer
    end

    test "accepts valid configuration" do
      changeset =
        OIDC.change(%Config{}, %{
          "enabled" => "true",
          "name" => "Google",
          "issuer" => "https://accounts.google.com",
          "client_id" => "client-123",
          "client_secret" => "super-secret"
        })

      assert changeset.valid?
    end
  end

  describe "domain_allowed?/2" do
    test "allows all when allowed_domains is empty or nil" do
      assert OIDC.domain_allowed?("alice@example.com", "")
      assert OIDC.domain_allowed?("alice@company.org", nil)
    end

    test "matches case-insensitively on comma or space-separated list" do
      domains = "company.com, partner.org  corp.net"
      assert OIDC.domain_allowed?("alice@company.com", domains)
      assert OIDC.domain_allowed?("BOB@PARTNER.ORG", domains)
      assert OIDC.domain_allowed?("carol@corp.net", domains)
      refute OIDC.domain_allowed?("dave@other.com", domains)
    end
  end

  describe "ID token verification" do
    setup do
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

      sign_jwt = fn payload, header_opts ->
        header = Map.merge(%{"alg" => "RS256", "kid" => "key-1", "typ" => "JWT"}, header_opts)
        header_b64 = Jason.encode!(header) |> Base.url_encode64(padding: false)
        payload_b64 = Jason.encode!(payload) |> Base.url_encode64(padding: false)
        signed_data = header_b64 <> "." <> payload_b64

        sig =
          :public_key.sign(signed_data, :sha256, private_key) |> Base.url_encode64(padding: false)

        signed_data <> "." <> sig
      end

      %{private_key: private_key, jwks: jwks, sign_jwt: sign_jwt}
    end

    test "verifies a valid token successfully", %{jwks: jwks, sign_jwt: sign_jwt} do
      now = System.system_time(:second)

      payload = %{
        "iss" => "https://auth.example.com",
        "sub" => "user-123",
        "aud" => "my-client-id",
        "exp" => now + 3600,
        "iat" => now,
        "nonce" => "test-nonce",
        "email" => "alice@example.com",
        "email_verified" => true,
        "name" => "Alice Cooper"
      }

      token = sign_jwt.(payload, %{})

      assert {:ok, claims} =
               OIDC.verify_id_token(
                 token,
                 jwks,
                 "https://auth.example.com",
                 "my-client-id",
                 "test-nonce"
               )

      assert claims["sub"] == "user-123"
      assert claims["email"] == "alice@example.com"
    end

    test "accepts aud as a list containing client_id", %{jwks: jwks, sign_jwt: sign_jwt} do
      now = System.system_time(:second)

      payload = %{
        "iss" => "https://auth.example.com",
        "sub" => "user-123",
        "aud" => ["other-client", "my-client-id"],
        "exp" => now + 3600,
        "nonce" => "test-nonce"
      }

      token = sign_jwt.(payload, %{})

      assert {:ok, _} =
               OIDC.verify_id_token(
                 token,
                 jwks,
                 "https://auth.example.com",
                 "my-client-id",
                 "test-nonce"
               )
    end

    test "rejects expired token", %{jwks: jwks, sign_jwt: sign_jwt} do
      now = System.system_time(:second)

      payload = %{
        "iss" => "https://auth.example.com",
        "sub" => "user-123",
        "aud" => "my-client-id",
        "exp" => now - 120,
        "nonce" => "test-nonce"
      }

      token = sign_jwt.(payload, %{})

      assert {:error, :invalid_token} =
               OIDC.verify_id_token(
                 token,
                 jwks,
                 "https://auth.example.com",
                 "my-client-id",
                 "test-nonce"
               )
    end

    test "rejects mismatched nonce", %{jwks: jwks, sign_jwt: sign_jwt} do
      now = System.system_time(:second)

      payload = %{
        "iss" => "https://auth.example.com",
        "sub" => "user-123",
        "aud" => "my-client-id",
        "exp" => now + 3600,
        "nonce" => "wrong-nonce"
      }

      token = sign_jwt.(payload, %{})

      assert {:error, :invalid_token} =
               OIDC.verify_id_token(
                 token,
                 jwks,
                 "https://auth.example.com",
                 "my-client-id",
                 "expected-nonce"
               )
    end

    test "rejects mismatched issuer", %{jwks: jwks, sign_jwt: sign_jwt} do
      now = System.system_time(:second)

      payload = %{
        "iss" => "https://evil.com",
        "sub" => "user-123",
        "aud" => "my-client-id",
        "exp" => now + 3600,
        "nonce" => "test-nonce"
      }

      token = sign_jwt.(payload, %{})

      assert {:error, :invalid_token} =
               OIDC.verify_id_token(
                 token,
                 jwks,
                 "https://auth.example.com",
                 "my-client-id",
                 "test-nonce"
               )
    end

    test "rejects token signed by untrusted key", %{sign_jwt: sign_jwt} do
      now = System.system_time(:second)

      payload = %{
        "iss" => "https://auth.example.com",
        "sub" => "user-123",
        "aud" => "my-client-id",
        "exp" => now + 3600,
        "nonce" => "test-nonce"
      }

      token = sign_jwt.(payload, %{})
      other_key = :public_key.generate_key({:rsa, 2048, 65537})
      {:RSAPrivateKey, _, n_int, e_int, _, _, _, _, _, _, _} = other_key

      untrusted_jwks = [
        %{
          "kty" => "RSA",
          "kid" => "key-1",
          "n" => :binary.encode_unsigned(n_int) |> Base.url_encode64(padding: false),
          "e" => :binary.encode_unsigned(e_int) |> Base.url_encode64(padding: false)
        }
      ]

      assert {:error, :invalid_token} =
               OIDC.verify_id_token(
                 token,
                 untrusted_jwks,
                 "https://auth.example.com",
                 "my-client-id",
                 "test-nonce"
               )
    end
  end

  describe "saving settings" do
    test "persists config and encrypts secret in Notebook.Secrets", %{scope: scope} do
      # Mock the probe endpoint for discovery
      Req.Test.stub(Notebook.OIDC, fn conn ->
        Req.Test.json(conn, %{
          "issuer" => "https://auth.example.com",
          "authorization_endpoint" => "https://auth.example.com/auth",
          "token_endpoint" => "https://auth.example.com/token",
          "jwks_uri" => "https://auth.example.com/jwks"
        })
      end)

      attrs = %{
        "enabled" => "true",
        "name" => "Okta Team",
        "issuer" => "https://auth.example.com",
        "client_id" => "client-xyz",
        "client_secret" => "super-secret-token",
        "allowed_domains" => "example.com",
        "auto_register" => "true",
        "password_login" => "false"
      }

      assert {:ok, config} = OIDC.save(scope, attrs)
      assert config.enabled == true
      assert config.name == "Okta Team"
      assert config.issuer == "https://auth.example.com"
      assert config.client_id == "client-xyz"
      assert config.allowed_domains == "example.com"
      assert config.auto_register == true
      assert config.password_login == false
      assert config.secret? == true

      # Secret is stored encrypted in Notebook.Secrets
      assert Notebook.Secrets.get("oidc.client_secret") == "super-secret-token"

      # Calling config() retrieves the saved config
      retrieved = OIDC.config()
      assert retrieved.enabled == true
      assert retrieved.name == "Okta Team"
      assert retrieved.secret? == true
    end
  end
end
