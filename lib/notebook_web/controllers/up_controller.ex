defmodule NotebookWeb.UpController do
  @moduledoc "The health check kamal-proxy polls: the notebook answers, and its database does."

  use NotebookWeb, :controller

  def index(conn, _params) do
    Ecto.Adapters.SQL.query!(Notebook.Repo, "SELECT 1")
    text(conn, "ok")
  end
end
