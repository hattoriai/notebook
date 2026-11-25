defmodule NotebookWeb.UpController do
  @moduledoc "The health check kamal-proxy polls: the notebook answers, and its database does."

  use NotebookWeb, :controller

  alias Ecto.Adapters.SQL

  def index(conn, _params) do
    SQL.query!(Notebook.Repo, "SELECT 1")
    text(conn, "ok")
  end
end
