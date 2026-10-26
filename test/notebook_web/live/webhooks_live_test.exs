defmodule NotebookWeb.WebhooksLiveTest do
  # Kunai's pages, mounted under the notebook's settings.
  use NotebookWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Notebook.AccountsFixtures

  setup do
    %{
      admin: user_fixture(%{name: "Hattori Hanzo", admin: true}),
      yuki: user_fixture(%{name: "Yuki Hattori"})
    }
  end

  test "only an admin sees the webhooks", %{conn: conn, yuki: yuki} do
    assert {:error, {:redirect, %{to: "/"}}} = live(log_in_user(conn, yuki), "/admin/webhooks")
  end

  test "an admin adds an endpoint, in the settings' frame, and is given its secret", %{
    conn: conn,
    admin: admin
  } do
    {:ok, view, html} = live(log_in_user(conn, admin), "/admin/webhooks")
    assert html =~ "Notebook settings"
    assert html =~ "Listen for this account"

    {:ok, view, _html} =
      view
      |> element("a", "Add endpoint")
      |> render_click()
      |> follow_redirect(conn |> log_in_user(admin))

    assert render(view) =~ "This notebook"

    html =
      view
      |> form("#kunai-endpoint-form",
        endpoint: %{url: "https://hooks.example.com/notebook", description: "Search index"}
      )
      |> render_submit()

    assert html =~ "Endpoint added"
    assert html =~ "whsec_"
    assert [%Kunai.Endpoint{owner: "notebook", events: ["*"]}] = Notebook.Repo.all(Kunai.Endpoint)
  end
end
