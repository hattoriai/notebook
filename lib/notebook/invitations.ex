defmodule Notebook.Invitations do
  @moduledoc """
  Who may create an account. A notebook is open to anyone, or invite only:
  then a person registers with a link an admin made (`create/1`), which
  works once and for #{7} days. The notebook's first person may always
  register, and becomes its admin (`Notebook.Accounts.register_user/1`).

  Only a token's hash is kept: an admin sees a link once, when they make
  it, and sends it as they like (the notebook may have no mail).
  """
  import Ecto.Query

  alias Notebook.{Accounts, Repo}
  alias Notebook.Accounts.{Scope, User}
  alias Notebook.Invitations.Invitation
  alias Notebook.Storage.Setting

  @days 7
  @setting "registration"

  @doc "Whether people join only with an admin's link."
  def invite_only? do
    case Repo.get(Setting, @setting) do
      %Setting{value: %{"invite_only" => true}} -> true
      _ -> false
    end
  end

  @doc "Makes the notebook invite only, or open to anyone. Only an admin may."
  def set_invite_only(scope, invite_only) when is_boolean(invite_only) do
    if Scope.admin?(scope) do
      value = %{"invite_only" => invite_only, "saved_by" => scope.user.id}

      Repo.insert!(%Setting{key: @setting, value: value},
        on_conflict: [set: [value: value, updated_at: DateTime.utc_now(:second)]],
        conflict_target: :key
      )

      {:ok, invite_only}
    else
      {:error, :forbidden}
    end
  end

  @doc """
  Whether a person may register now, with this token or none: anyone in
  an open notebook, or one with no one yet; else only with a usable link.
  """
  def open?(token \\ nil) do
    not invite_only?() or not Repo.exists?(User) or match?(%Invitation{}, usable(token))
  end

  @doc "Makes a link's token. Only an admin may. The token is shown once."
  def create(scope) do
    if Scope.admin?(scope) do
      token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
      expires_at = DateTime.utc_now(:second) |> DateTime.add(@days, :day)

      invitation =
        Repo.insert!(%Invitation{
          token_hash: hash(token),
          invited_by_id: scope.user.id,
          expires_at: expires_at
        })

      {:ok, invitation, token}
    else
      {:error, :forbidden}
    end
  end

  @doc "The links not used yet and not expired, the newest first."
  def pending do
    now = DateTime.utc_now(:second)

    Repo.all(
      from i in Invitation,
        where: is_nil(i.used_at) and i.expires_at > ^now,
        order_by: [desc: i.inserted_at, desc: i.id],
        preload: :invited_by
    )
  end

  @doc "Takes a link back before anyone uses it. Only an admin may."
  def revoke(scope, id) do
    with true <- Scope.admin?(scope) || {:error, :forbidden},
         %Invitation{used_at: nil} = invitation <- Repo.get(Invitation, id) do
      Repo.delete(invitation)
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Registers a person, if they may (`open?/1`): with a link, the link is
  used by them, and no one else may use it.
  """
  def register(attrs, token \\ nil) do
    Repo.transact(fn ->
      cond do
        not open?(token) ->
          {:error, :invite_only}

        invitation = invite_only?() && usable(token) ->
          with {:ok, user} <- Accounts.register_user(attrs) do
            invitation
            |> Ecto.Changeset.change(used_at: DateTime.utc_now(:second), used_by_id: user.id)
            |> Repo.update!()

            {:ok, user}
          end

        true ->
          Accounts.register_user(attrs)
      end
    end)
  end

  defp usable(token) when is_binary(token) and token != "" do
    now = DateTime.utc_now(:second)

    Repo.one(
      from i in Invitation,
        where: i.token_hash == ^hash(token) and is_nil(i.used_at) and i.expires_at > ^now
    )
  end

  defp usable(_token), do: nil

  defp hash(token), do: :crypto.hash(:sha256, token)
end
