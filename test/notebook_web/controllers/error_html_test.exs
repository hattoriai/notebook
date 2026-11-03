defmodule NotebookWeb.ErrorHTMLTest do
  use NotebookWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template, only: [render_to_string: 4]

  test "a page not found: in the notebook's paper and ink, with the way home" do
    html = render_to_string(NotebookWeb.ErrorHTML, "404", "html", [])
    assert html =~ ~s(id="error-404")
    assert html =~ "This page isn&#39;t in the notebook."
    assert html =~ "Go to Notebook"
    # Its styles from the notebook's own address, for a site's proxy too.
    assert html =~ NotebookWeb.Endpoint.url() <> "/assets/css/app"
  end

  test "a page that broke, which asks nothing of the database" do
    html = render_to_string(NotebookWeb.ErrorHTML, "500", "html", [])
    assert html =~ ~s(id="error-500")
    assert html =~ "The ink spilled."
    assert html =~ "Try again"
  end

  test "an unknown address, through the app, is the notebook's 404", %{conn: conn} do
    {404, _headers, body} = assert_error_sent(404, fn -> get(conn, "/no-such-page-at-all") end)
    assert body =~ ~s(id="error-404")
  end
end
