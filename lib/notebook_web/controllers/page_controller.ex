defmodule NotebookWeb.PageController do
  use NotebookWeb, :controller

  alias Notebook.Invitations
  alias NotebookWeb.PageHTML

  @doc """
  The notebook's front page, for those not signed in (`NotebookWeb.UserAuth`
  shows it at `/` in place of the pages, which ask for a person).
  """
  def home(conn, _params) do
    render(conn, :home,
      page_title: "Pages you host yourself",
      invite_only: Invitations.invite_only?(),
      libraries: PageHTML.libraries()
    )
  end

  @doc "The open-source libraries the notebook is made with."
  def made_with(conn, _params) do
    render(conn, :made_with, page_title: "Made with", libraries: PageHTML.libraries())
  end
end
