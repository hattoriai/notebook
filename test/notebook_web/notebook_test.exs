defmodule NotebookWeb.NotebookTest do
  use NotebookWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Notebook.{Accounts, Pages, Repo}
  alias Notebook.Accounts.Scope

  test "registration asks for name and password and signs in without email confirmation", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/users/register")
    assert has_element?(view, "#registration_form input[name='user[name]']")
    assert has_element?(view, "#registration_form input[name='user[password]']")

    conn =
      post(conn, ~p"/users/register", %{
        "user" => %{
          "name" => "Nina Writer",
          "email" => "nina@example.test",
          "password" => "long enough password"
        }
      })

    assert redirected_to(conn) == ~p"/"
    user = Accounts.get_user_by_email("nina@example.test")
    assert user.name == "Nina Writer"
    assert user.confirmed_at
    assert user.hashed_password
  end

  test "pages require login and a member can create and find rich content", %{conn: conn} do
    assert redirected_to(get(conn, ~p"/")) == ~p"/users/log-in"

    {:ok, user} =
      Accounts.register_user(%{
        name: "Nina Writer",
        email: "nina@example.test",
        password: "long enough password"
      })

    conn = log_in_user(conn, user)
    assert {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Your shared notebook"

    content = Kotoba.Content.from_markdown("## Notes\n\nA useful sentence.")
    {:ok, page} = Pages.create(Scope.for_user(user), %{title: "Release notes", body: content})
    assert Enum.any?(Pages.list("useful"), &(&1.id == page.id))
    assert {:ok, _view, html} = live(conn, ~p"/pages/#{page.id}")
    assert html =~ "Release notes"
    assert html =~ "A useful sentence."
  end

  test "collaboration store keeps content with revision and rejects stale saves" do
    {:ok, user} =
      Accounts.register_user(%{
        name: "Nina Writer",
        email: "nina@example.test",
        password: "long enough password"
      })

    {:ok, page} = Pages.create(Scope.for_user(user), %{title: "Shared"})
    id = to_string(page.id)
    assert {:ok, %{state: nil}} = Notebook.CollabStore.load(Repo, id)
    state = %{"epoch" => "epoch-1", "revision" => 1}
    content = Kotoba.Content.empty()
    assert :ok = Notebook.CollabStore.save(Repo, id, nil, state, content)
    assert {:error, :conflict} = Notebook.CollabStore.save(Repo, id, nil, state, content)
    assert {:ok, %{state: ^state}} = Notebook.CollabStore.load(Repo, id)
  end
end
