defmodule Notebook.Permissions.FolderPolicy do
  @moduledoc false
  # A folder is its space's: its members' roles are their roles on it; and
  # a folder in a folder is its parent's. Its editors share it, and its
  # pages with it, with a person or with anyone who has a link (to read).
  use Sekisho.Policy, for: Notebook.Spaces.Folder
  import Ecto.Query

  permissions([:read, :comment, :edit, :manage])

  role(:viewer, permissions: [:read])
  role(:commenter, permissions: [:comment])
  role(:editor, permissions: [:edit])
  role(:admin, permissions: [:manage])

  derive(:editor, from: :admin)
  derive(:commenter, from: :editor)
  derive(:viewer, from: :commenter)

  derive(:admin, from: {:space, :admin})
  derive(:editor, from: {:space, :editor})
  derive(:commenter, from: {:space, :commenter})
  derive(:viewer, from: {:space, :viewer})

  derive(:admin, from: {:parent, :admin})
  derive(:editor, from: {:parent, :editor})
  derive(:commenter, from: {:parent, :commenter})
  derive(:viewer, from: {:parent, :viewer})

  grant_to([:user, :link], by: :edit, link_up_to: :viewer)

  # In a space off limits to agents.
  @impl true
  def deny(%Notebook.Accounts.User{as_agent: true}, _permission) do
    closed = from(s in Notebook.Spaces.Space, where: s.closed_to_agents, select: s.id)
    dynamic([f], f.space_id in subquery(closed))
  end

  def deny(_actor, _permission), do: false
end
