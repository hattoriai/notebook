defmodule Notebook.Storage.Setting do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:key, :string, autogenerate: false}
  schema "settings" do
    field :value, :map, default: %{}
    timestamps(type: :utc_datetime)
  end
end
