defmodule Notebook.ChartsTest do
  # SQLite takes one writer at a time: these write a lot, so they run alone.
  use Notebook.DataCase, async: false

  import Notebook.AccountsFixtures

  alias Notebook.Accounts.Scope
  alias Notebook.{Charts, Pages, Repo, Spaces}
  alias Notebook.Pages.Row

  setup do
    hanzo = user_fixture(%{name: "Hattori Hanzo"})
    yuki = user_fixture(%{name: "Yuki Hattori"})
    scope = Scope.for_user(hanzo)
    {:ok, forge} = Spaces.create_team(scope, %{name: "The forge"})

    {:ok, blades} =
      Pages.create(scope, %{"title" => "Blades", "kind" => "table", "space_id" => forge.id})

    for {title, status, points} <- [
          {"Fold", "done", 5},
          {"Quench", "doing", 3},
          {"Polish", "todo", 8}
        ] do
      Repo.insert!(%Row{page_id: blades.id, title: title, status: status, points: points})
    end

    # A text in General, which Yuki reads; the table is in The forge, which she does not.
    {:ok, numbers} = Pages.create(scope, %{"title" => "Numbers"})
    {:ok, chart} = Charts.create(scope, numbers, blades, "points_by_status")

    %{
      hanzo: hanzo,
      yuki: yuki,
      scope: scope,
      yuki_scope: Scope.for_user(yuki),
      blades: blades,
      numbers: numbers,
      chart: chart
    }
  end

  defp ctx(user) do
    Issho.Tool.Context.new(
      Notebook.Issho,
      %{id: "agent:#{user.id}", name: "Claude Code", kind: :agent},
      on_behalf_of: user
    )
  end

  test "a chart of a preset draws its table's rows", %{
    scope: scope,
    numbers: numbers,
    chart: chart
  } do
    assert %{"title" => "Points by status"} = chart.spec

    assert %{chart: %{id: id}, rows: rows} =
             Charts.embeddable(scope, numbers)[to_string(chart.id)]

    assert id == chart.id
    assert Enum.map(rows, & &1.points) == [5, 3, 8]

    assert {:error, :no_preset} =
             Charts.create(scope, numbers, Repo.get!(Pages.Page, chart.source_id), "pie")
  end

  test "only who reads the table sees the chart's data", %{
    yuki_scope: yuki_scope,
    numbers: numbers,
    chart: chart
  } do
    assert Charts.embeddable(yuki_scope, numbers) == %{}
    assert Charts.get(yuki_scope, chart.id) == nil

    assert Notebook.Embeds.render(
             yuki_scope,
             %{kind: "chart", ref: to_string(chart.id)},
             :markdown
           ) == nil
  end

  test "a chart is its words and its table in the page's Markdown", %{scope: scope, chart: chart} do
    markdown =
      Notebook.Embeds.render(scope, %{kind: "chart", ref: to_string(chart.id)}, :markdown)

    assert markdown =~ "**Points by status**"
    assert markdown =~ "| todo | 8 |"
  end

  test "a chart is made by who edits the page and reads the table", %{
    yuki_scope: yuki_scope,
    numbers: numbers,
    blades: blades
  } do
    assert {:error, %Sekisho.Denied{}} =
             Charts.create(yuki_scope, numbers, blades, "points_by_status")
  end

  test "an agent reads a chart's table and changes the chart, and the page hears it", %{
    hanzo: hanzo,
    yuki: yuki,
    numbers: numbers,
    chart: chart
  } do
    room = Notebook.Collaboration.room(numbers)
    document = Charts.document(chart)
    Phoenix.PubSub.subscribe(Notebook.PubSub, Charts.topic(numbers.id))

    {:ok, read} = Fude.Issho.Tools.Read.call(%{room: room, chart: document}, ctx(hanzo))

    assert %{
             "columns" => ["Status", "Points"],
             "rows" => [["done", 5], ["doing", 3], ["todo", 8]]
           } = read["shows"]

    spec = Map.put(read["spec"], "title", "How far the blades have come")

    assert {:ok, _} =
             Fude.Issho.Tools.Change.call(%{room: room, chart: document, spec: spec}, ctx(hanzo))

    assert_receive {:chart_changed, id}
    assert id == chart.id
    assert Repo.get!(Charts.Chart, chart.id).spec["title"] == "How far the blades have come"

    # Yuki's agent is in the page's room, and does not read the table.
    {:ok, read} = Fude.Issho.Tools.Read.call(%{room: room, chart: document}, ctx(yuki))
    assert %{"errors" => [_]} = read["shows"]
  end

  test "the page's agents find its charts", %{numbers: numbers, chart: chart} do
    assert %{"use" => %{"charts" => [%{"chart" => document, "title" => "Points by status"}]}} =
             Notebook.Tools.describe(numbers)

    assert document == Charts.document(chart)
  end
end
