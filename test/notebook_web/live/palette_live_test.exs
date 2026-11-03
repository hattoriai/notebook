defmodule NotebookWeb.PaletteLiveTest do
  use NotebookWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Jumon.Test
  import Notebook.AccountsFixtures

  setup do
    %{admin: user_fixture(%{name: "Hattori Hanzo", admin: true}), yuki: user_fixture()}
  end

  test "the palette is on every page of a person signed in", %{conn: conn, admin: admin} do
    conn = log_in_user(conn, admin)

    for path <-
          ~w(/ /inbox /archive /agents /account/settings /account/settings/password /account/settings/notifications /notebook/settings /notebook/settings/agents /notebook/settings/bots /notebook/settings/files) do
      {:ok, view, _html} = live(conn, path)
      assert has_element?(view, "#jumon[phx-hook='Jumon']"), "no palette at #{path}"
      assert "Notebook settings" in (view |> actions() |> names()), "no actions at #{path}"
    end
  end

  test "the palette has the sidebar's links, and an admin's own", %{conn: conn, admin: admin} do
    {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/")
    names = view |> actions() |> names()

    for name <- ["New space", "Inbox", "Archive", "Agents", "Bots", "Notebook settings"],
        do: assert(name in names, "no #{name}")
  end

  test "no admin, no admin's links", %{conn: conn, yuki: yuki} do
    {:ok, view, _html} = live(log_in_user(conn, yuki), ~p"/")
    names = view |> actions() |> names()

    assert "Agents" in names
    refute "Bots" in names
    refute "Notebook settings" in names
  end

  test "a search finds the spaces", %{conn: conn, yuki: yuki} do
    {:ok, view, _html} = live(log_in_user(conn, yuki), ~p"/")
    spaces = view |> search("genral") |> Enum.filter(&(&1["source"] == "spaces"))
    assert [%{"name" => "General"}] = spaces
  end
end
