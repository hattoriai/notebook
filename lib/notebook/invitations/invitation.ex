defmodule Notebook.Invitations.Invitation do
  @moduledoc "A link to join an invite-only notebook: used once, before it expires."
  use Ecto.Schema

  schema "invitations" do
    field :token_hash, :binary, redact: true
    field :used_at, :utc_datetime
    field :expires_at, :utc_datetime
    belongs_to :invited_by, Notebook.Accounts.User
    belongs_to :used_by, Notebook.Accounts.User

    timestamps(type: :utc_datetime)
  end
end
