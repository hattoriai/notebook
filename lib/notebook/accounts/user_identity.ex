defmodule Notebook.Accounts.UserIdentity do
  @moduledoc """
  An external identity (OpenID Connect) linked to a person: its provider
  (e.g. "oidc"), the provider's issuer URL, and the person's unique
  subject identifier (`uid` / "sub").
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_identities" do
    field :provider, :string
    field :uid, :string
    field :issuer, :string
    field :email, :string
    belongs_to :user, Notebook.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(identity, attrs) do
    identity
    |> cast(attrs, [:provider, :uid, :issuer, :email, :user_id])
    |> validate_required([:provider, :uid, :issuer, :user_id])
    |> unique_constraint([:provider, :issuer, :uid])
  end
end
