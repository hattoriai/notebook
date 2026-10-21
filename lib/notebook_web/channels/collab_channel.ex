defmodule NotebookWeb.CollabChannel do
  @moduledoc "The rooms of the pages, for the browsers that join them (Issho)."
  use Issho.Channel, instance: Notebook.Issho
end
