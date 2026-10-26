defmodule Notebook.ToolsTest do
  # SQLite takes one writer at a time: these write a lot, so they run alone.
  use Notebook.DataCase, async: false

  import Notebook.AccountsFixtures

  alias Notebook.Accounts.Scope
  alias Notebook.Actions.CreatePage
  alias Notebook.Tools.ListPages
  alias Notebook.{Pages, Spaces}

  setup do
    hanzo = user_fixture(%{name: "Hattori Hanzo"})
    yuki = user_fixture(%{name: "Yuki Hattori"})
    scope = Scope.for_user(hanzo)
    {:ok, forge} = Spaces.create_team(scope, %{name: "The forge"})
    {:ok, _} = Spaces.add_member(scope, forge, yuki, "commenter")
    {:ok, _} = Pages.create(scope, %{"title" => "The last blade", "space_id" => forge.id})

    {:ok, _} =
      Pages.create(scope, %{"title" => "A letter", "space_id" => Spaces.private!(hanzo).id})

    %{hanzo: hanzo, yuki: yuki, forge: forge}
  end

  # An agent's context, as NotebookWeb.MCP makes it for a person's token.
  defp ctx(user) do
    Issho.Tool.Context.new(
      Notebook.Issho,
      %{id: "agent:#{user.id}", name: "Claude Code", kind: :agent},
      on_behalf_of: user
    )
  end

  test "an agent lists the pages its person may read, with their space", %{
    hanzo: hanzo,
    yuki: yuki
  } do
    {:ok, %{"pages" => pages}} = ListPages.call(%{}, ctx(hanzo))
    assert %{"space" => "The forge"} = Enum.find(pages, &(&1["title"] == "The last blade"))
    assert Enum.any?(pages, &(&1["title"] == "A letter"))

    {:ok, %{"pages" => pages}} = ListPages.call(%{}, ctx(yuki))
    assert Enum.any?(pages, &(&1["title"] == "The last blade"))
    refute Enum.any?(pages, &(&1["title"] == "A letter"))

    {:ok, %{"pages" => pages}} = ListPages.call(%{space: "Private"}, ctx(hanzo))
    assert ["A letter"] == Enum.map(pages, & &1["title"])
  end

  test "an agent makes pages in a space its person edits, which list_pages gives", %{
    hanzo: hanzo,
    yuki: yuki
  } do
    {:ok, %{"spaces" => spaces}} = ListPages.call(%{}, ctx(yuki))
    assert %{"id" => private} = Enum.find(spaces, &(&1["name"] == "Private"))
    refute Enum.any?(spaces, &(&1["name"] == "The forge"))

    assert {:ok, %{"space" => "Private"}} =
             CreatePage.call(%{title: "Draft", kind: "text", space_id: private}, ctx(yuki))

    {:ok, %{"spaces" => spaces}} = ListPages.call(%{}, ctx(hanzo))
    assert %{"id" => forge} = Enum.find(spaces, &(&1["name"] == "The forge"))

    assert {:ok, %{"space" => "The forge", "space_id" => ^forge}} =
             CreatePage.call(%{title: "Plan", kind: "board", space_id: forge}, ctx(hanzo))

    assert {:error, "The room's policy does not allow this."} =
             CreatePage.call(%{title: "Mine", kind: "text", space_id: forge}, ctx(yuki))
  end
end
