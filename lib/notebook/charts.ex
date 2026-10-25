defmodule Notebook.Charts do
  @moduledoc """
  Charts in text pages (Fude). A chart draws the rows of a table page, its
  source, and lives in a text page as an embed. Its spec is a shared
  document of the page's room (`Fude.Issho`): people and agents change
  it, an agent with `change_chart`, and everyone on the page sees it move.

  A chart's data is its source's rows: only someone who may read the
  table sees them, in the page, in its Markdown and in an agent's
  `read_chart`. Anyone else sees the chart's title.
  """
  import Ecto.Query

  alias Notebook.Accounts.Scope
  alias Notebook.Charts.Chart
  alias Notebook.Pages.{Page, Row}
  alias Notebook.{Pages, Repo}

  @presets [
    {"points_by_status", "Points by status", "How far the work has come"},
    {"tasks_by_owner", "Tasks by owner", "Who has what"},
    {"due_by_week", "Due by week", "When the work falls due"}
  ]

  @doc "The charts a table offers to make: `{key, title, about}`."
  def presets, do: @presets

  # The chart of a preset, with the source's title under it.
  defp preset("points_by_status", source),
    do:
      Fude.bar(x: :status, y: {:sum, :points}, title: "Points by status", subtitle: source.title)

  defp preset("tasks_by_owner", source),
    do:
      Fude.bar(
        x: :owner,
        y: {:count, :title},
        horizontal: true,
        title: "Tasks by owner",
        subtitle: source.title
      )

  defp preset("due_by_week", source),
    do:
      Fude.bar(
        x: {:week, :due_on},
        y: {:count, :title},
        color: :status,
        title: "Due by week",
        subtitle: source.title
      )

  @doc """
  Makes a chart of a preset in a text page, of a table page's rows: the
  scope edits the page and reads the table.
  """
  def create(scope, %Page{kind: "text"} = page, %Page{kind: "table"} = source, preset)
      when is_binary(preset) do
    with :ok <- Pages.authorize(scope, :edit, page),
         :ok <- Pages.authorize(scope, :read, source),
         true <- List.keymember?(@presets, preset, 0) || {:error, :no_preset} do
      spec = preset |> preset(source) |> Fude.Spec.dump()
      Repo.insert(%Chart{page_id: page.id, source_id: source.id, spec: spec})
    end
  end

  @doc """
  The charts of a text page that the scope may see drawn, by id (as an
  embed's ref): each with its source and its rows.
  """
  def embeddable(scope, %Page{id: id}) do
    from(c in Chart, where: c.page_id == ^id, preload: :source)
    |> Repo.all()
    |> Enum.filter(&Pages.allowed?(scope, :read, &1.source))
    |> Map.new(&{to_string(&1.id), %{chart: &1, rows: rows(&1.source_id)}})
  end

  @doc "A chart the scope may see drawn (it reads its source), or nil."
  def get(scope, id) do
    with %Chart{} = chart <- Repo.get(Chart, id) |> Repo.preload(:source),
         true <- Pages.allowed?(scope, :read, chart.source) do
      chart
    else
      _ -> nil
    end
  end

  @doc "A table page's rows, as a chart reads them."
  def rows(source_id) do
    Repo.all(
      from r in Row,
        where: r.page_id == ^source_id,
        order_by: r.id,
        select: %{
          title: r.title,
          status: r.status,
          owner: r.owner,
          due_on: r.due_on,
          points: r.points
        }
    )
  end

  @doc "A chart's document in its page's room."
  def document(%Chart{id: id, page_id: page_id}), do: "page:#{page_id}/chart:#{id}"

  @doc "The shared document of a chart (Issho's policy): its spec, saved as it changes."
  def shared(chart_id) do
    case Repo.get(Chart, chart_id) do
      %Chart{} = chart -> Fude.Issho.document(chart.spec, on_change: &save(chart.id, &1, &2))
      nil -> {:error, :not_found}
    end
  end

  defp save(id, fude_chart, _context) do
    spec = Fude.Spec.dump(fude_chart)

    case Repo.get(Chart, id) do
      nil ->
        {:error, :not_found}

      chart ->
        chart |> Ecto.Changeset.change(spec: spec) |> Repo.update!()
        Phoenix.PubSub.broadcast(Notebook.PubSub, topic(chart.page_id), {:chart_changed, id})
        :ok
    end
  end

  @doc "The topic of a page's charts: `{:chart_changed, id}` when one changes."
  def topic(page_id), do: "page-charts:#{page_id}"

  @doc """
  The rows an agent's chart draws (`config :fude, Fude.Issho, data:`):
  its source's, when the person it works for may read them.
  """
  def data("page:" <> rest, ctx) do
    with [_page, "chart:" <> id] <- String.split(rest, "/"),
         %Scope{} = scope <- Notebook.Tools.scope(ctx),
         %Chart{} = chart <- get(scope, id) do
      {:ok, rows(chart.source_id)}
    else
      _ -> {:error, "The person you work for may not read this chart's table."}
    end
  end

  def data(_document, _ctx), do: :none

  @doc """
  Watches the tables of a page's charts for the calling LiveView: it gets
  `{:chart_rows, source_id}` when a row of one changes. Masu's hook takes
  the grids' messages, so a process linked to the LiveView listens for it.
  """
  def watch_rows(source_ids) do
    me = self()

    for id <- Enum.uniq(source_ids) do
      ref = make_ref()

      spawn_link(fn ->
        Phoenix.PubSub.subscribe(Notebook.PubSub, "page-rows:#{id}")
        send(me, {:watching, ref})
        relay(me, id)
      end)

      # Back once it listens, so that no change after this call is missed.
      receive do
        {:watching, ^ref} -> :ok
      end
    end

    :ok
  end

  defp relay(to, id) do
    receive do
      _change ->
        send(to, {:chart_rows, id})
        relay(to, id)
    end
  end
end
