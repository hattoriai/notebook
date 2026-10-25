defmodule NotebookWeb.NotFound do
  @moduledoc "Nothing at a path: no page of the notebook, and no published one (a 404)."
  defexception message: "Not found", plug_status: 404
end
