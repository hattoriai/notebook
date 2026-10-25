defmodule Notebook.Secrets.Secret do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:name, :string, autogenerate: false}
  schema "secrets" do
    field :value, Notebook.Encrypted.Binary, redact: true
    timestamps(type: :utc_datetime)
  end
end
