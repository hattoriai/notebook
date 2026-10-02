defmodule NotebookWeb.PageController do
  use NotebookWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
