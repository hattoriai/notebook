defmodule Notebook.Permissions.PagePolicy do
  @moduledoc false
  # A page is its space's, as a folder is, and its folder's: a folder
  # shared with someone shares its pages. Its editors share it with a
  # person, or with anyone who has a link (to read, or to comment too).
  use Sekisho.Policy, for: Notebook.Pages.Page

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

  derive(:admin, from: {:folder, :admin})
  derive(:editor, from: {:folder, :editor})
  derive(:commenter, from: {:folder, :commenter})
  derive(:viewer, from: {:folder, :viewer})

  grant_to([:user, :link], by: :edit, link_up_to: :commenter)
end
