defmodule Notebook.Vault do
  @moduledoc """
  The keys of the notebook's secrets (`Notebook.Secrets`): a
  [Strongbox](https://hexdocs.pm/strongbox) vault. Each secret is tagged
  with the key that encrypted it, so that keys rotate.

  The key is `NOTEBOOK_VAULT_KEY` (32 bytes, Base64: `openssl rand
  -base64 32`), or else one derived from `SECRET_KEY_BASE`, so that a
  notebook needs nothing more to start. To rotate: set the new key, keep
  the old ones in `NOTEBOOK_VAULT_RETIRED_KEYS` (Base64, separated by
  commas), restart, then re-encrypt with `Notebook.Secrets.rotate/0`.
  The key derived from `SECRET_KEY_BASE` is always among the retired, so
  setting a key the first time needs no more.

  The vault is no process: the keys are read once, when the notebook
  starts (`load/0`).
  """
  use Strongbox

  alias Plug.Crypto.KeyGenerator

  # The key that encrypts now, then the retired ones that still open. Each
  # is there twice: as Strongbox writes, and as the notebook's vault of
  # before did (Cloak's AES.GCM, with a 12-byte IV), so that the secrets
  # of before still open.
  @impl true
  def keys, do: :persistent_term.get(__MODULE__, nil) || load()

  @doc """
  Reads the keys from the environment, keeps them for `keys/0`, and gives
  them. Raises when a key is not 32 bytes in Base64.
  """
  def load do
    derived = derived()

    {default, retired} =
      case configured("NOTEBOOK_VAULT_KEY") do
        [key] -> {key, configured("NOTEBOOK_VAULT_RETIRED_KEYS") ++ [derived]}
        [] -> {derived, configured("NOTEBOOK_VAULT_RETIRED_KEYS")}
      end

    keys = [default | retired |> Enum.uniq() |> Enum.reject(&(&1 == default))]

    keys =
      Enum.map(keys, &%{tag: tag(&1), key: &1}) ++
        Enum.map(keys, &%{tag: "AES.GCM." <> tag(&1), key: &1, format: :cloak, iv_length: 12})

    :persistent_term.put(__MODULE__, keys)
    keys
  end

  @doc "The tag of the key that encrypts now, as each secret carries it."
  def tag do
    [%{tag: tag} | _retired] = keys()
    tag
  end

  @doc false
  def tag(key), do: :crypto.hash(:sha256, key) |> binary_part(0, 4) |> Base.encode16(case: :lower)

  defp derived do
    secret_key_base = Application.fetch_env!(:notebook, NotebookWeb.Endpoint)[:secret_key_base]
    KeyGenerator.generate(secret_key_base, "notebook vault", length: 32)
  end

  defp configured(variable) do
    (System.get_env(variable) || "")
    |> String.split(",", trim: true)
    |> Enum.map(fn encoded ->
      case Base.decode64(String.trim(encoded)) do
        {:ok, <<_::binary-size(32)>> = key} ->
          key

        _bad ->
          raise ArgumentError, "#{variable} must be 32 bytes in Base64 (openssl rand -base64 32)"
      end
    end)
  end
end
