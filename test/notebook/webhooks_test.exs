defmodule Notebook.WebhooksTest do
  use Notebook.DataCase, async: true

  import Notebook.AccountsFixtures

  alias Notebook.{Pages, Spaces}
  alias Notebook.Accounts.Scope

  setup do
    user = user_fixture(%{name: "Nina Writer"})
    %{scope: Scope.for_user(user), user: user}
  end

  defp events, do: Repo.all(from e in Kunai.Event, order_by: e.id)

  test "a page's changes are its events, by whoever made them", %{scope: scope, user: user} do
    {:ok, page} = Pages.create(scope, %{"title" => "Lisbon trip"})
    {:ok, page} = Pages.update(scope, page, %{title: "Porto trip"})
    {:ok, page} = Pages.archive(scope, page)
    {:ok, _page} = Pages.restore(scope, page)

    assert [created, updated, archived, restored] = events()

    assert {created.type, archived.type, restored.type} ==
             {"page.created", "page.archived", "page.restored"}

    assert %{type: "page.updated", owner: "notebook", object_id: object_id} = updated
    assert object_id == to_string(page.id)
    assert updated.data["title"] == "Porto trip"
    assert updated.data["space"]["name"] == Spaces.general!().name
    assert updated.previous == %{"title" => "Lisbon trip"}

    assert updated.actor == %{
             "type" => "user",
             "id" => to_string(user.id),
             "name" => "Nina Writer"
           }
  end

  test "a change that changes nothing tracked, or a Private page's, sends nothing", %{
    scope: scope,
    user: user
  } do
    {:ok, page} =
      Pages.create(scope, %{"title" => "Mine", "space_id" => Spaces.private!(user).id})

    {:ok, _page} = Pages.update(scope, page, %{title: "Still mine"})
    assert events() == []

    {:ok, page} = Pages.create(scope, %{"title" => "Ours"})
    {:ok, _page} = Pages.update(scope, page, %{title: "Ours"})
    assert [%{type: "page.created"}] = events()
  end
end
