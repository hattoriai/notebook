defmodule Notebook.Permissions.SpacePolicy do
  @moduledoc false
  use Sekisho.Policy, for: Notebook.Spaces.Space

  permissions([:read, :comment, :edit, :manage])

  role(:viewer, permissions: [:read])
  role(:commenter, permissions: [:comment])
  role(:editor, permissions: [:edit])
  role(:admin, permissions: [:manage])

  derive(:editor, from: :admin)
  derive(:commenter, from: :editor)
  derive(:viewer, from: :commenter)
end
