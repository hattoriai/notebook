defmodule NotebookWeb.MCP.OAuthTest do
  use NotebookWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Notebook.AccountsFixtures

  alias Notebook.Accounts.Scope
  alias Notebook.Agents

  setup do
    %{admin: user_fixture(%{name: "Hattori Hanzo", admin: true}), yuki: user_fixture()}
  end

  defp oauth!(admin), do: {:ok, true} = Agents.set_oauth(Scope.for_user(admin), true)

  describe "with tokens only, the default" do
    test "there is no OAuth server, and a client without a token is told of the Agents page",
         %{conn: conn} do
      refute Agents.oauth?()

      assert conn |> get("/.well-known/oauth-authorization-server") |> response(404)
      assert conn |> get("/.well-known/oauth-protected-resource/mcp") |> response(404)
      assert build_conn() |> post("/oauth/token", %{}) |> response(404)

      conn = post(build_conn(), "/mcp", %{})
      assert response(conn, 401) =~ "Agents page"
      assert get_resp_header(conn, "www-authenticate") == []
    end
  end

  describe "with OAuth" do
    setup %{admin: admin} do
      oauth!(admin)
      :ok
    end

    test "the OAuth server answers, and a client without a token is told where to sign in",
         %{conn: conn} do
      assert %{"issuer" => _, "authorization_endpoint" => _} =
               conn |> get("/.well-known/oauth-authorization-server") |> json_response(200)

      conn = post(build_conn(), "/mcp", %{})
      assert conn.status == 401
      assert [challenge] = get_resp_header(conn, "www-authenticate")
      assert challenge =~ "resource_metadata"
    end

    test "the consent page asks a person to sign in first", %{conn: conn} do
      assert redirected_to(get(conn, "/oauth/authorize")) == ~p"/users/log-in"
    end

    test "an agent's token still connects, as that agent", %{admin: admin} do
      {:ok, _agent, token} =
        Agents.create(Scope.for_user(admin), %{"name" => "Scribe", "lifetime" => "90"})

      client =
        Sake.Test.connect(NotebookWeb.MCP,
          plug: NotebookWeb.Endpoint,
          headers: [{"authorization", "Bearer " <> token}]
        )

      assert {:ok, tools} = Sake.Test.list_tools(client)
      assert Enum.any?(tools, &(&1.name == "list_actors"))
    end

    test "turned off, OAuth is gone again", %{admin: admin, conn: conn} do
      {:ok, false} = Agents.set_oauth(Scope.for_user(admin), false)
      assert conn |> get("/.well-known/oauth-authorization-server") |> response(404)
    end
  end

  describe "the subject" do
    test "a person, by their id; not a bot, nor anyone after OAuth is off", %{
      admin: admin,
      yuki: yuki
    } do
      alias NotebookWeb.MCP.Subject

      assert {:ok, %{id: id}} = Subject.fetch(Subject.id(yuki))
      assert id == yuki.id
      assert :error = Subject.fetch("user:nope")
      assert :error = Subject.fetch("agent:1")

      refute Subject.authorize_resource?(yuki, "/mcp")
      oauth!(admin)
      assert Subject.authorize_resource?(yuki, "/mcp")
    end
  end

  describe "Notebook settings" do
    test "an admin turns OAuth on and off", %{conn: conn, admin: admin} do
      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/admin")

      view |> element("#connecting-form") |> render_change(%{"connecting" => "oauth"})
      assert Agents.oauth?()

      view |> element("#connecting-form") |> render_change(%{"connecting" => "token"})
      refute Agents.oauth?()
    end

    test "only an admin may", %{yuki: yuki} do
      assert {:error, :forbidden} = Agents.set_oauth(Scope.for_user(yuki), true)
      refute Agents.oauth?()
    end

    test "the Agents page shows the command without a token when OAuth is on", %{
      conn: conn,
      admin: admin,
      yuki: yuki
    } do
      {:ok, view, _html} = live(log_in_user(conn, yuki), ~p"/agents")
      refute has_element?(view, "#agent-oauth")

      oauth!(admin)
      {:ok, view, _html} = live(log_in_user(conn, yuki), ~p"/agents")
      assert has_element?(view, "#oauth-claude-command", "/mcp")
      assert has_element?(view, "#oauth-claude-command-copy[data-copy*=\"/mcp\"]")
      assert has_element?(view, "#oauth-codex-command-copy[data-copy*=\"/mcp\"]")
    end
  end
end
