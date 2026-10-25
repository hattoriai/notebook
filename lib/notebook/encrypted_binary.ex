defmodule Notebook.Encrypted.Binary do
  @moduledoc "A field encrypted by `Notebook.Vault`."
  use Cloak.Ecto.Binary, vault: Notebook.Vault
end
