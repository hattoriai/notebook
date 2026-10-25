defmodule Notebook.Permissions.Sources do
  @moduledoc false
  # The roles people hold, from the spaces' members.
  use Sekisho.Sources
  import Ecto.Query

  @impl true
  def roles(Notebook.Spaces.Space) do
    from m in Notebook.Spaces.Member,
      select: %{actor_id: m.user_id, resource_id: m.space_id, role: m.role}
  end
end
