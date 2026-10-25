defmodule Notebook.Permissions.FolderPolicy do
  @moduledoc false
  # A folder is its space's: its members' roles are their roles on it.
  use Sekisho.Policy, for: Notebook.Spaces.Folder

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
end
