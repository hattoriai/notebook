defmodule Notebook.Encrypted.Binary do
  @moduledoc "A field encrypted by `Notebook.Vault`: a secret no key opens does not load."
  use Ecto.Type

  @impl true
  def type, do: :binary

  @impl true
  def cast(value) when is_binary(value), do: {:ok, value}
  def cast(_value), do: :error

  @impl true
  def dump(value) when is_binary(value), do: {:ok, Notebook.Vault.encrypt(value)}
  def dump(_value), do: :error

  @impl true
  def load(value) when is_binary(value), do: Notebook.Vault.decrypt(value)
  def load(_value), do: :error
end
