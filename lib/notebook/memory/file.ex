defmodule Notebook.Memory.File do
  @moduledoc false
  use Ecto.Schema

  schema "memory_files" do
    belongs_to :agent, Notebook.Agents.Agent
    field :path, :string
    field :content, :string
    field :directory, :boolean, default: false
    timestamps(type: :utc_datetime_usec)
  end
end
