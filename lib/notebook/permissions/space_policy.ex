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

  # Off limits to agents, with all in it.
  @impl true
  def deny(%Notebook.Accounts.User{as_agent: true}, _permission),
    do: dynamic([s], s.closed_to_agents)

  def deny(_actor, _permission), do: false
end
