defmodule NotebookWeb.UpControllerTest do
  use NotebookWeb.ConnCase, async: true

  test "the health check answers without anyone signed in", %{conn: conn} do
    assert text_response(get(conn, ~p"/up"), 200) == "ok"
  end
end
