defmodule Notebook.Permissions.SpacePolicy do
  @moduledoc false
  use Sekisho.Policy, for: Notebook.Spaces.Space
  import Ecto.Query

  permissions([:read, :comment, :edit, :manage])

  role(:viewer, permissions: [:read])
  role(:commenter, permissions: [:comment])
  role(:editor, permissions: [:edit])
  role(:admin, permissions: [:manage])

  derive(:editor, from: :admin)
  derive(:commenter, from: :editor)
  derive(:viewer, from: :commenter)

  # Off limits to agents, with all in it. In the Archive, a space is only
  # its admins' to restore or delete (`:manage`), and no agent's.
  @impl true
  def deny(%Notebook.Accounts.User{as_agent: true}, _permission),
    do: dynamic([s], s.closed_to_agents or not is_nil(s.archived_at))

  def deny(_actor, :manage), do: false
  def deny(_actor, _permission), do: dynamic([s], not is_nil(s.archived_at))
end
