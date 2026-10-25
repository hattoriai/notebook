defmodule Notebook.Vault do
  @moduledoc """
  The key of the notebook's secrets (`Notebook.Secrets`), with Cloak:
  AES-256-GCM, each secret tagged with the key that encrypted it, so that
  keys rotate.

  The key is `NOTEBOOK_VAULT_KEY` (32 bytes, Base64: `openssl rand
  -base64 32`), or else one derived from `SECRET_KEY_BASE`, so that a
  notebook needs nothing more to start. To rotate: set the new key, keep
  the old ones in `NOTEBOOK_VAULT_RETIRED_KEYS` (Base64, separated by
  commas), restart, then re-encrypt with `Notebook.Secrets.rotate/0`.
  The key derived from `SECRET_KEY_BASE` is always among the retired, so
  setting a key the first time needs no more.
  """
  use Cloak.Vault, otp_app: :notebook

  @impl GenServer
  def init(config) do
    derived = derived()

    {default, retired} =
      case configured("NOTEBOOK_VAULT_KEY") do
        [key] -> {key, configured("NOTEBOOK_VAULT_RETIRED_KEYS") ++ [derived]}
        [] -> {derived, configured("NOTEBOOK_VAULT_RETIRED_KEYS")}
      end

    retired = retired |> Enum.uniq() |> Enum.reject(&(&1 == default))

    ciphers =
      [default: cipher(default)] ++
        Enum.with_index(retired, fn key, n -> {:"retired_#{n}", cipher(key)} end)

    {:ok, Keyword.put(config, :ciphers, ciphers)}
  end

  @doc "The tag of the key that encrypts now, as each secret carries it."
  def tag, do: tag(current_key())

  @doc false
  def tag(key),
    do:
      "AES.GCM." <>
        (:crypto.hash(:sha256, key) |> binary_part(0, 4) |> Base.encode16(case: :lower))

  defp current_key do
    case configured("NOTEBOOK_VAULT_KEY") do
      [key] -> key
      [] -> derived()
    end
  end

  # Each key's tag is its fingerprint: a secret names the key it needs.
  defp cipher(key), do: {Cloak.Ciphers.AES.GCM, tag: tag(key), key: key, iv_length: 12}

  defp derived do
    secret_key_base = Application.fetch_env!(:notebook, NotebookWeb.Endpoint)[:secret_key_base]
    Plug.Crypto.KeyGenerator.generate(secret_key_base, "notebook vault", length: 32)
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
