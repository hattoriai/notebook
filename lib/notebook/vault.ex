defmodule Notebook.Vault do
  @moduledoc """
  The key of the notebook's secrets (`Notebook.Secrets`): AES-256-GCM
  (Erlang's `:crypto`), each secret tagged with the key that encrypted
  it, so that keys rotate.

  The key is `NOTEBOOK_VAULT_KEY` (32 bytes, Base64: `openssl rand
  -base64 32`), or else one derived from `SECRET_KEY_BASE`, so that a
  notebook needs nothing more to start. To rotate: set the new key, keep
  the old ones in `NOTEBOOK_VAULT_RETIRED_KEYS` (Base64, separated by
  commas), restart, then re-encrypt with `Notebook.Secrets.rotate/0`.
  The key derived from `SECRET_KEY_BASE` is always among the retired, so
  setting a key the first time needs no more.
  """
  use Agent

  # A secret is as Cloak's AES.GCM kept it (the notebook's secrets before
  # 0.x), so that those still open: the key's tag (a type byte, its length,
  # the tag), a 12-byte IV, the 16-byte GCM tag, then the ciphertext.
  @aad "AES256GCM"
  @iv 12

  @doc false
  def start_link(_opts), do: Agent.start_link(&keys/0, name: __MODULE__)

  # The key that encrypts now, then the retired ones that still open.
  defp keys do
    derived = derived()

    {default, retired} =
      case configured("NOTEBOOK_VAULT_KEY") do
        [key] -> {key, configured("NOTEBOOK_VAULT_RETIRED_KEYS") ++ [derived]}
        [] -> {derived, configured("NOTEBOOK_VAULT_RETIRED_KEYS")}
      end

    [default | retired |> Enum.uniq() |> Enum.reject(&(&1 == default))]
  end

  @doc "Encrypts `plaintext` with the key of now."
  def encrypt(plaintext) when is_binary(plaintext) do
    [key | _retired] = Agent.get(__MODULE__, & &1)
    tag = tag(key)
    iv = :crypto.strong_rand_bytes(@iv)

    {ciphertext, gcm_tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, plaintext, @aad, true)

    <<1, byte_size(tag), tag::binary, iv::binary, gcm_tag::binary, ciphertext::binary>>
  end

  @doc "Decrypts what `encrypt/1` gave, with the key its tag names: `{:ok, plaintext}`, or `:error` when no key opens it."
  def decrypt(
        <<1, size, tag::binary-size(size), iv::binary-size(@iv), gcm_tag::binary-16,
          ciphertext::binary>>
      ) do
    with key when is_binary(key) <- Enum.find(Agent.get(__MODULE__, & &1), &(tag(&1) == tag)),
         plaintext when is_binary(plaintext) <-
           :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, ciphertext, @aad, gcm_tag, false) do
      {:ok, plaintext}
    else
      _none -> :error
    end
  end

  def decrypt(_value), do: :error

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
