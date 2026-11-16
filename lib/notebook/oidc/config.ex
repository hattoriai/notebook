defmodule Notebook.OIDC.Config do
  @moduledoc """
  The notebook's OpenID Connect configuration:
    * `enabled`: whether OIDC sign-in is offered
    * `name`: provider name on the button (e.g. "Google", "Okta", "Single Sign-On")
    * `issuer`: the OIDC provider's discovery URL
    * `client_id`: OAuth client ID
    * `client_secret`: OAuth client secret (redacted in forms)
    * `allowed_domains`: comma/space separated list of allowed email domains (e.g. "company.com")
    * `auto_register`: whether users from this IdP can join even if invite-only
    * `password_login`: whether local password login is still allowed alongside OIDC
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :enabled, :boolean, default: false
    field :name, :string, default: "Single Sign-On"
    field :issuer, :string, default: ""
    field :client_id, :string, default: ""
    field :client_secret, :string, redact: true
    field :secret?, :boolean, virtual: true, default: false
    field :allowed_domains, :string, default: ""
    field :auto_register, :boolean, default: false
    field :password_login, :boolean, default: true
  end

  def changeset(config, attrs) do
    config
    |> cast(attrs, [
      :enabled,
      :name,
      :issuer,
      :client_id,
      :client_secret,
      :allowed_domains,
      :auto_register,
      :password_login
    ])
    |> update_change(:name, &trim/1)
    |> update_change(:issuer, &trim/1)
    |> update_change(:client_id, &trim/1)
    |> update_change(:client_secret, &trim/1)
    |> update_change(:allowed_domains, &trim/1)
    |> validate_oidc()
  end

  defp trim(val) when is_binary(val), do: String.trim(val)
  defp trim(val), do: val

  defp validate_oidc(changeset) do
    if get_field(changeset, :enabled) do
      changeset
      |> validate_required([:name, :issuer, :client_id])
      |> validate_secret()
      |> validate_issuer()
    else
      changeset
    end
  end

  defp validate_secret(changeset) do
    secret = get_change(changeset, :client_secret)

    if get_field(changeset, :secret?) or (is_binary(secret) and secret != "") do
      changeset
    else
      add_error(changeset, :client_secret, "is needed for OpenID Connect")
    end
  end

  defp validate_issuer(changeset) do
    case get_field(changeset, :issuer) do
      issuer when is_binary(issuer) and issuer != "" ->
        case URI.parse(issuer) do
          %URI{scheme: scheme, host: host}
          when scheme in ["http", "https"] and host not in [nil, ""] ->
            changeset

          _ ->
            add_error(changeset, :issuer, "must be an address starting with https://")
        end

      _ ->
        changeset
    end
  end
end
