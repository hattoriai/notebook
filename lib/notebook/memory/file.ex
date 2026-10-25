defmodule Notebook.Memory.File do
  @moduledoc false
  use Ecto.Schema

  schema "memory_files" do
    belongs_to :agent, Notebook.Agents.Agent
    field :path, :string
    field :content, :string
    field :directory, :boolean, default: false
    # The pages it was learned on: the rooms its agent was in as it wrote.
    field :sources, {:array, :integer}, default: []
    timestamps(type: :utc_datetime_usec)
  end
end
