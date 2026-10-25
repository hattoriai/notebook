defmodule Notebook.Agents.Agent do
  @moduledoc """
  An agent a person connected (Claude Code, Codex, any MCP client): its
  name, the person it works for, and its token, kept as a hash.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "agents" do
    belongs_to :user, Notebook.Accounts.User
    field :name, :string
    # What its person tells it to be: its /memories/self.md (Notebook.Memory).
    field :instructions, :string, default: ""
    field :token_hash, :binary, redact: true
    field :token_hint, :string
    field :expires_at, :utc_datetime
    field :last_seen_at, :utc_datetime
    field :revoked_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(agent, attrs) do
    agent
    |> cast(attrs, [:name, :instructions])
    |> update_change(:name, &(&1 |> String.replace(~r/\s+/u, " ") |> String.trim()))
    |> validate_required([:name], message: "give it a name people will see")
    |> validate_length(:name, max: 60)
    |> validate_length(:instructions, max: 8_000)
  end
end
