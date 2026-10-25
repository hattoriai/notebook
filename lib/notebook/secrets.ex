defmodule Notebook.Secrets do
  @moduledoc """
  The notebook's secrets, by name: a bucket's key (`Notebook.Storage`),
  and the tokens and webhook secrets to come. Each is encrypted in the
  database by `Notebook.Vault`, and never leaves it but to the code that
  uses it.
  """
  import Ecto.Query, only: [select: 3, where: 2]

  alias Notebook.Repo
  alias Notebook.Secrets.Secret

  @doc "The secret named `name`, or nil (also when no key opens it)."
  def get(name) do
    case Repo.get(Secret, name) do
      %Secret{value: value} -> value
      nil -> nil
    end
  rescue
    # A key that is gone (`NOTEBOOK_VAULT_KEY` changed, the old one not
    # kept): the secret is to be given again.
    _error in [Cloak.MissingCipher, ArgumentError] -> nil
  end

  @doc "Keeps `value` as the secret named `name`."
  def put(name, value) when is_binary(name) and is_binary(value) do
    Repo.insert!(%Secret{name: name, value: value},
      on_conflict: [set: [value: value, updated_at: DateTime.utc_now(:second)]],
      conflict_target: :name
    )

    :ok
  end

  @doc "Forgets the secret named `name`."
  def delete(name) do
    Secret |> where(name: ^name) |> Repo.delete_all()
    :ok
  end

  @doc """
  Encrypts every secret again with the key of now (`Notebook.Vault`):
  after a key is changed, so that the old one can go. Gives the number
  encrypted again; a secret no key opens is left as it is.

      bin/notebook eval "Notebook.Secrets.rotate()"
  """
  def rotate do
    Secret
    |> select([s], s.name)
    |> Repo.all()
    |> Enum.count(fn name ->
      case get(name) do
        nil -> false
        value -> put(name, value) == :ok
      end
    end)
  end
end
