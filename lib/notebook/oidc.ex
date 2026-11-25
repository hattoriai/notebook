defmodule Notebook.OIDC do
  @moduledoc """
  OpenID Connect authentication for human users.

  Supports any OIDC Discovery provider (Keycloak, Google, Okta, Authentik,
  Microsoft Entra ID, etc.) using native Erlang/OTP crypto and `:req`.
  """
  import Ecto.Changeset, only: [apply_action: 2]

  alias Notebook.Accounts.Scope
  alias Notebook.OIDC.Config
  alias Notebook.Repo
  alias Notebook.Storage.Setting

  @setting "oidc"
  @secret "oidc.client_secret"
  @topic "oidc"

  @doc "Subscribe to OIDC configuration changes."
  def subscribe, do: Phoenix.PubSub.subscribe(Notebook.PubSub, @topic)

  defp broadcast(msg), do: Phoenix.PubSub.broadcast(Notebook.PubSub, @topic, msg)

  @doc "The current OIDC configuration."
  def config do
    stored = stored()
    secret = secret(stored)

    %Config{
      enabled: value_bool(stored["enabled"], env_bool("NOTEBOOK_OIDC_ENABLED", false)),
      name: stored["name"] || env("NOTEBOOK_OIDC_NAME", "Single Sign-On"),
      issuer: stored["issuer"] || env("NOTEBOOK_OIDC_ISSUER", ""),
      client_id: stored["client_id"] || env("NOTEBOOK_OIDC_CLIENT_ID", ""),
      client_secret: nil,
      secret?: is_binary(secret) and secret != "",
      allowed_domains: stored["allowed_domains"] || env("NOTEBOOK_OIDC_ALLOWED_DOMAINS", ""),
      auto_register:
        value_bool(stored["auto_register"], env_bool("NOTEBOOK_OIDC_AUTO_REGISTER", false)),
      password_login:
        value_bool(stored["password_login"], env_bool("NOTEBOOK_OIDC_PASSWORD_LOGIN", true))
    }
  end

  @doc "A changeset for the OIDC configuration form."
  def change(%Config{} = config, attrs \\ %{}) do
    Config.changeset(config, attrs)
  end

  @doc """
  Saves OIDC settings for an admin.
  When enabling, the provider's discovery URL is probed first.
  """
  def save(%Scope{} = scope, attrs) do
    if Scope.admin?(scope) do
      stored = stored()
      current_secret = secret(stored)
      config = %{config() | client_secret: nil, secret?: current_secret != nil}

      changeset = Config.changeset(config, attrs)

      with {:ok, new_config} <- apply_action(changeset, :save),
           :ok <- maybe_probe(new_config, changeset) do
        new_secret = attrs["client_secret"] || attrs[:client_secret]

        if is_binary(new_secret) and String.trim(new_secret) != "" do
          Notebook.Secrets.put(@secret, String.trim(new_secret))
        end

        value = %{
          "enabled" => new_config.enabled,
          "name" => new_config.name,
          "issuer" => new_config.issuer,
          "client_id" => new_config.client_id,
          "allowed_domains" => new_config.allowed_domains,
          "auto_register" => new_config.auto_register,
          "password_login" => new_config.password_login,
          "saved_by" => scope.user.id
        }

        Repo.insert!(%Setting{key: @setting, value: value},
          on_conflict: [set: [value: value, updated_at: DateTime.utc_now(:second)]],
          conflict_target: :key
        )

        broadcast({:oidc, :saved})
        {:ok, config()}
      end
    else
      {:error, :forbidden}
    end
  end

  defp maybe_probe(%Config{enabled: true} = config, changeset) do
    case probe(config.issuer) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error,
         changeset
         |> Ecto.Changeset.add_error(:issuer, "couldn't be reached: " <> describe_error(reason))
         |> Map.put(:action, :save)}
    end
  end

  defp maybe_probe(_config, _changeset), do: :ok

  @doc "Whether local email/password login is allowed."
  def password_login_allowed? do
    cfg = config()
    not cfg.enabled or cfg.password_login
  end

  @doc "Whether a given email matches the allowed domains."
  def domain_allowed?(email, allowed_domains \\ nil)

  def domain_allowed?(email, nil) do
    domain_allowed?(email, config().allowed_domains)
  end

  def domain_allowed?(email, allowed_domains) when is_binary(email) do
    case parse_domains(allowed_domains) do
      [] ->
        true

      domains ->
        [_user, domain] = String.split(email, "@", parts: 2)
        domain = String.downcase(domain)
        Enum.any?(domains, &(&1 == domain))
    end
  end

  def domain_allowed?(_, _), do: false

  defp parse_domains(nil), do: []

  defp parse_domains(str) when is_binary(str) do
    str
    |> String.split(~r/[,\s]+/, trim: true)
    |> Enum.map(&String.downcase/1)
  end

  ## Protocol & Verification

  @doc "Discovers OIDC configuration from the issuer URL."
  def discover(issuer) when is_binary(issuer) do
    issuer = String.trim_trailing(issuer, "/")
    url = issuer <> "/.well-known/openid-configuration"

    case Req.get(url, req_options(redirect: true, receive_timeout: 10_000)) do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
        with true <-
               is_binary(body["authorization_endpoint"]) || {:error, :missing_auth_endpoint},
             true <- is_binary(body["token_endpoint"]) || {:error, :missing_token_endpoint},
             true <- is_binary(body["jwks_uri"]) || {:error, :missing_jwks_uri} do
          {:ok, body}
        end

      {:ok, %Req.Response{status: status}} ->
        {:error, "provider returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc "Checks if the provider discovery URL can be contacted and parsed."
  def probe(issuer) do
    case discover(issuer) do
      {:ok, _metadata} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Builds the authorization redirect URL with PKCE and state/nonce.
  """
  def authorize_url(issuer, client_id, redirect_uri) do
    with {:ok, metadata} <- discover(issuer) do
      state = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
      nonce = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
      code_verifier = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
      code_challenge = :crypto.hash(:sha256, code_verifier) |> Base.url_encode64(padding: false)

      params = %{
        "client_id" => client_id,
        "response_type" => "code",
        "scope" => "openid email profile",
        "redirect_uri" => redirect_uri,
        "state" => state,
        "nonce" => nonce,
        "code_challenge" => code_challenge,
        "code_challenge_method" => "S256"
      }

      auth_endpoint = metadata["authorization_endpoint"]
      uri = URI.parse(auth_endpoint)
      existing_query = URI.decode_query(uri.query || "")
      merged_query = URI.encode_query(Map.merge(existing_query, params))
      final_url = URI.to_string(%{uri | query: merged_query})

      {:ok,
       %{
         url: final_url,
         state: state,
         nonce: nonce,
         code_verifier: code_verifier
       }}
    end
  end

  @doc """
  Exchanges an authorization code for tokens, verifies the ID token,
  and returns normalized user claims.
  """
  def authenticate(code, code_verifier, expected_nonce, redirect_uri) do
    cfg = config()

    with true <- cfg.enabled || {:error, :oidc_disabled},
         secret when is_binary(secret) and secret != "" <-
           secret(stored()) || {:error, :missing_client_secret},
         {:ok, metadata} <- discover(cfg.issuer),
         {:ok, token_response} <-
           exchange_code(
             metadata["token_endpoint"],
             code,
             code_verifier,
             redirect_uri,
             cfg.client_id,
             secret
           ),
         id_token when is_binary(id_token) <-
           token_response["id_token"] || {:error, :missing_id_token},
         {:ok, jwks} <- fetch_jwks(metadata["jwks_uri"]),
         {:ok, claims} <-
           verify_id_token(id_token, jwks, metadata["issuer"], cfg.client_id, expected_nonce) do
      access_token = token_response["access_token"]
      claims = maybe_fetch_userinfo(claims, metadata["userinfo_endpoint"], access_token)

      {:ok,
       %{
         sub: to_string(claims["sub"]),
         issuer: to_string(claims["iss"] || metadata["issuer"]),
         email: claims["email"],
         email_verified: claims["email_verified"] in [true, "true", 1, "1"],
         name: claims["name"] || claims["preferred_username"],
         claims: claims
       }}
    end
  end

  defp exchange_code(token_endpoint, code, code_verifier, redirect_uri, client_id, client_secret) do
    form_data = [
      grant_type: "authorization_code",
      code: code,
      redirect_uri: redirect_uri,
      client_id: client_id,
      client_secret: client_secret,
      code_verifier: code_verifier
    ]

    auth_header = "Basic " <> Base.encode64("#{client_id}:#{client_secret}")

    options =
      req_options(
        url: token_endpoint,
        form: form_data,
        headers: [{"authorization", auth_header}, {"accept", "application/json"}]
      )

    case Req.post(options) do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, "token endpoint returned status #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_jwks(jwks_uri) do
    case Req.get(jwks_uri, req_options(receive_timeout: 10_000)) do
      {:ok, %Req.Response{status: 200, body: %{"keys" => keys}}} when is_list(keys) ->
        {:ok, keys}

      {:ok, %Req.Response{status: status}} ->
        {:error, "jwks endpoint returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc "Verifies an ID token against JWKS keys, issuer, client_id, and nonce."
  def verify_id_token(id_token, jwks, expected_issuer, client_id, expected_nonce) do
    with [header_b64, payload_b64, sig_b64] <- String.split(id_token, "."),
         {:ok, header_json} <- base64url_decode(header_b64),
         {:ok, header} <- Jason.decode(header_json),
         {:ok, payload_json} <- base64url_decode(payload_b64),
         {:ok, payload} <- Jason.decode(payload_json),
         {:ok, sig} <- base64url_decode(sig_b64),
         signed_data = header_b64 <> "." <> payload_b64,
         :ok <- verify_signature(header, signed_data, sig, jwks),
         :ok <- validate_claims(payload, expected_issuer, client_id, expected_nonce) do
      {:ok, payload}
    else
      _ -> {:error, :invalid_token}
    end
  end

  defp verify_signature(%{"alg" => alg} = header, signed_data, sig, jwks) do
    kid = header["kid"]
    keys = Enum.filter(jwks, fn k -> is_nil(kid) or k["kid"] == kid end)

    Enum.find_value(keys, {:error, :key_not_found}, fn key ->
      if verify_key(alg, signed_data, sig, key), do: :ok
    end)
  end

  defp verify_signature(_header, _signed_data, _sig, _jwks), do: {:error, :unsupported_algorithm}

  # RSA algorithms (RS256, RS384, RS512)
  defp verify_key(alg, signed_data, sig, %{"kty" => "RSA", "n" => n_b64, "e" => e_b64})
       when alg in ["RS256", "RS384", "RS512"] do
    with {:ok, n_bin} <- base64url_decode(n_b64),
         {:ok, e_bin} <- base64url_decode(e_b64) do
      n = :crypto.bytes_to_integer(n_bin)
      e = :crypto.bytes_to_integer(e_bin)
      rsa_key = {:RSAPublicKey, n, e}
      digest_type = rsa_digest(alg)
      :public_key.verify(signed_data, digest_type, sig, rsa_key)
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  # ECDSA algorithm (ES256)
  defp verify_key("ES256", signed_data, sig, %{
         "kty" => "EC",
         "crv" => "P-256",
         "x" => x_b64,
         "y" => y_b64
       }) do
    with {:ok, x_bin} <- base64url_decode(x_b64),
         {:ok, y_bin} <- base64url_decode(y_b64),
         true <- byte_size(sig) == 64 do
      <<r_bin::binary-size(32), s_bin::binary-size(32)>> = sig
      r = :crypto.bytes_to_integer(r_bin)
      s = :crypto.bytes_to_integer(s_bin)
      der_sig = :public_key.der_encode(:ECDSA_Sig_Value, {:ECDSA_Sig_Value, r, s})
      point = <<4, x_bin::binary, y_bin::binary>>
      ec_key = {point, {:namedCurve, :secp256r1}}
      :public_key.verify(signed_data, :sha256, der_sig, ec_key)
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  # EdDSA (Ed25519)
  defp verify_key("EdDSA", signed_data, sig, %{"kty" => "OKP", "crv" => "Ed25519", "x" => x_b64}) do
    with {:ok, pub_key} <- base64url_decode(x_b64) do
      :crypto.verify(:eddsa, :none, signed_data, sig, [pub_key, :ed25519])
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp verify_key(_alg, _signed_data, _sig, _key), do: false

  defp rsa_digest("RS256"), do: :sha256
  defp rsa_digest("RS384"), do: :sha384
  defp rsa_digest("RS512"), do: :sha512

  defp validate_claims(claims, expected_issuer, client_id, expected_nonce) do
    now = System.system_time(:second)
    exp = claims["exp"]
    nbf = claims["nbf"]
    iss = claims["iss"]
    aud = claims["aud"]
    nonce = claims["nonce"]

    cond do
      not is_integer(exp) or exp <= now - 60 ->
        {:error, :token_expired}

      is_integer(nbf) and nbf > now + 60 ->
        {:error, :token_not_yet_valid}

      not issuer_matches?(iss, expected_issuer) ->
        {:error, :issuer_mismatch}

      not audience_matches?(aud, client_id) ->
        {:error, :audience_mismatch}

      is_binary(expected_nonce) and
          (not is_binary(nonce) or not Plug.Crypto.secure_compare(nonce, expected_nonce)) ->
        {:error, :nonce_mismatch}

      true ->
        :ok
    end
  end

  defp issuer_matches?(nil, _), do: false
  defp issuer_matches?(iss, expected), do: normalize_url(iss) == normalize_url(expected)

  defp audience_matches?(aud, client_id) when is_binary(aud), do: aud == client_id

  defp audience_matches?(aud, client_id) when is_list(aud),
    do: Enum.member?(aud, client_id)

  defp audience_matches?(_, _), do: false

  defp normalize_url(url) when is_binary(url), do: String.trim_trailing(url, "/")
  defp normalize_url(_), do: ""

  defp maybe_fetch_userinfo(claims, endpoint, access_token)
       when is_binary(endpoint) and is_binary(access_token) do
    needs_email = is_nil(claims["email"])
    needs_name = is_nil(claims["name"])

    if needs_email or needs_name do
      options =
        req_options(
          headers: [{"authorization", "Bearer " <> access_token}, {"accept", "application/json"}]
        )

      case Req.get(endpoint, options) do
        {:ok, %Req.Response{status: 200, body: userinfo}} when is_map(userinfo) ->
          # Verify sub matches if present
          if is_nil(userinfo["sub"]) or userinfo["sub"] == claims["sub"] do
            Map.merge(userinfo, claims)
          else
            claims
          end

        _ ->
          claims
      end
    else
      claims
    end
  end

  defp maybe_fetch_userinfo(claims, _endpoint, _token), do: claims

  defp req_options(opts) when is_list(opts) do
    config_opts = Keyword.get(Application.get_env(:notebook, __MODULE__, []), :req, [])
    Keyword.merge(opts, config_opts)
  end

  @doc "Base64URL decode with padding tolerance."
  def base64url_decode(str) when is_binary(str) do
    padding = rem(byte_size(str), 4)

    padded =
      case padding do
        2 -> str <> "=="
        3 -> str <> "="
        _ -> str
      end

    Base.url_decode64(padded)
  end

  ## Helpers

  defp stored do
    case Repo.get(Setting, @setting) do
      %Setting{value: value} when is_map(value) -> value
      _ -> %{}
    end
  end

  defp secret(stored) do
    Notebook.Secrets.get(@secret) || stored["client_secret"] || env("NOTEBOOK_OIDC_CLIENT_SECRET")
  end

  defp env(name, default \\ nil) do
    case System.get_env(name) do
      nil -> default
      "" -> default
      val -> val
    end
  end

  defp env_bool(name, default) do
    case System.get_env(name) do
      nil -> default
      val -> val in ~w(true 1 yes)
    end
  end

  defp value_bool(val, _default) when is_boolean(val), do: val
  defp value_bool(_val, default), do: default

  defp describe_error({:error, reason}), do: describe_error(reason)
  defp describe_error(reason) when is_binary(reason), do: reason
  defp describe_error(reason), do: inspect(reason)
end
