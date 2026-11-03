defmodule NotebookWeb.PageControllerTest do
  use NotebookWeb.ConnCase, async: true

  import Notebook.AccountsFixtures

  alias Notebook.Accounts.Scope

  test "the front page greets those not signed in", %{conn: conn} do
    user_fixture(%{admin: true})
    doc = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert LazyHTML.query(doc, "#landing") |> Enum.count() == 1
    assert LazyHTML.query(doc, "#landing-log-in") |> Enum.count() == 1
    assert LazyHTML.query(doc, "#landing-register") |> Enum.count() == 1
    assert LazyHTML.query(doc, ".site-made a[href='/made-with']") |> Enum.count() == 1
  end

  test "invite only, the front page offers no account", %{conn: conn} do
    admin = user_fixture(%{admin: true})
    {:ok, true} = Notebook.Invitations.set_invite_only(Scope.for_user(admin), true)
    doc = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert LazyHTML.query(doc, "#landing-register") |> Enum.count() == 0
    assert LazyHTML.query(doc, "#landing-invite-only") |> Enum.count() == 1
  end

  test "a person signed in gets their pages, not the front page", %{conn: conn} do
    conn = conn |> log_in_user(user_fixture()) |> get(~p"/")
    doc = conn |> html_response(200) |> LazyHTML.from_document()
    assert LazyHTML.query(doc, "#landing") |> Enum.count() == 0
  end

  test "the other pages still ask for a person", %{conn: conn} do
    assert redirected_to(get(conn, ~p"/inbox")) == ~p"/users/log-in"
  end

  test "Made with lists the libraries, with their logos", %{conn: conn} do
    doc = conn |> get(~p"/made-with") |> html_response(200) |> LazyHTML.from_document()

    for library <- NotebookWeb.PageHTML.libraries() do
      assert LazyHTML.query(doc, "#library-#{library.id}") |> Enum.count() == 1

      assert File.exists?(
               Path.join(:code.priv_dir(:notebook), "static/images/libraries/#{library.id}.svg")
             )
    end
  end
end
