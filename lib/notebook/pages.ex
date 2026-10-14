defmodule Notebook.Pages do
  @moduledoc """
  The pages of the notebook. Notebook is one shared space: every signed-in
  account reads and edits every page. A page keeps the account that made it
  as its author.
  """
  import Ecto.Query
  alias Notebook.Accounts.Scope
  alias Notebook.Pages.Page
  alias Notebook.Repo

  def list(query \\ "") do
    search = "%" <> String.trim(query) <> "%"

    from(d in Page,
      where:
        like(d.title, ^search) or
          fragment("coalesce(json_extract(?, '$.text'), '') LIKE ?", d.body, ^search),
      order_by: [desc: d.updated_at],
      preload: :author
    )
    |> Repo.all()
  end

  def get!(id), do: Page |> Repo.get!(id) |> Repo.preload(:author)
  def get(id), do: Repo.get(Page, id)
  def change(page, attrs \\ %{}), do: Page.changeset(page, attrs)
  @doc "Creates a page with the scope's user as its author."
  def create(%Scope{user: user}, attrs) do
    %Page{author_id: user.id}
    |> Page.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, page} -> {:ok, Repo.preload(page, :author)}
      error -> error
    end
  end

  def update(page, attrs) do
    with {:ok, page} <- page |> Page.changeset(attrs) |> Repo.update(),
         do: {:ok, Repo.preload(page, :author, force: true)}
  end

  def publish(page, content) do
    page
    |> Ecto.Changeset.change(body: content)
    |> Repo.update()
  end

  @doc """
  The pages that have something on a day: due, covering it, reviewed or
  revisited then. `pages` are already loaded, as the index has them.
  """
  def on_day(pages, %Date{} = day), do: Enum.filter(pages, &(events(&1, day, day) != []))

  @doc """
  What each page has on the days of `range`, for the index calendar: a
  map from each day to a list of `{kind, page}`, where kind is `:due`,
  `:covers`, `:review` or `:revisit`.
  """
  def agenda(pages, %Date.Range{first: first, last: last}) do
    for page <- pages, {day, kind} <- events(page, first, last), reduce: %{} do
      acc -> Map.update(acc, day, [{kind, page}], &(&1 ++ [{kind, page}]))
    end
  end

  defp events(page, first, last) do
    within = &(Date.compare(&1, first) != :lt and Date.compare(&1, last) != :gt)

    due = if page.due_on && within.(page.due_on), do: [{page.due_on, :due}], else: []
    review_day = page.review_at && DateTime.to_date(local(page.review_at))
    review = if review_day && within.(review_day), do: [{review_day, :review}], else: []

    covers =
      case page.covers do
        %Date.Range{} = covers -> for day <- covers, within.(day), do: {day, :covers}
        nil -> []
      end

    due ++ review ++ covers ++ revisits(page, first, last)
  end

  defp revisits(%Page{revisit: nil}, _first, _last), do: []

  defp revisits(%Page{revisit: rule} = page, first, last) do
    rule
    |> Koyomi.Recurrence.between(revisit_start(page), first, last)
    |> Enum.map(&{&1, :revisit})
  end

  @doc "The first day of a page's revisits: its due day, else the day it was made."
  def revisit_start(%Page{due_on: %Date{} = due}), do: due
  def revisit_start(%Page{inserted_at: %DateTime{} = at}), do: DateTime.to_date(at)
  def revisit_start(%Page{}), do: Date.utc_today()

  @doc "The next revisit of a page from today, or nil."
  def next_revisit(%Page{revisit: nil}), do: nil

  def next_revisit(%Page{revisit: rule} = page) do
    today = Koyomi.Rules.today(Page.review_rules())

    rule
    |> Koyomi.Recurrence.occurrences(revisit_start(page))
    |> Enum.find(&(Date.compare(&1, today) != :lt))
  end

  @doc """
  The free review times of the days of `range`, for the review picker:
  every hour from 10:00 to 16:00 on weekdays, with the hours that another
  page's review takes disabled.
  """
  def review_slots(%Date.Range{first: first, last: last} = range, except_id \\ nil) do
    zone = time_zone()
    starts = first |> DateTime.new!(~T[00:00:00], zone) |> DateTime.shift_zone!("Etc/UTC")

    ends =
      last |> Date.add(1) |> DateTime.new!(~T[00:00:00], zone) |> DateTime.shift_zone!("Etc/UTC")

    taken =
      from(p in Page,
        where: p.review_at >= ^starts and p.review_at < ^ends,
        select: {p.review_at, p.title}
      )
      |> exclude_page(except_id)
      |> Repo.all()
      |> Map.new(fn {at, title} -> {DateTime.to_naive(local(at)), title} end)

    for day <- range, Date.day_of_week(day) in 1..5, into: %{} do
      slots =
        for hour <- 10..16 do
          time = Time.new!(hour, 0, 0)

          case Map.fetch(taken, NaiveDateTime.new!(day, time)) do
            {:ok, title} -> %{time: time, label: "Taken: #{title}", disabled: true}
            :error -> %{time: time}
          end
        end

      free = Enum.count(slots, &(!Map.get(&1, :disabled)))
      {day, [slots: slots, title: "#{free} free #{if free == 1, do: "time", else: "times"}"]}
    end
  end

  defp exclude_page(query, nil), do: query
  defp exclude_page(query, id), do: where(query, [p], p.id != ^id)

  @doc "The time zone of the notebook's dates (`config :koyomi, :time_zone`)."
  def time_zone, do: Application.get_env(:koyomi, :time_zone, "Etc/UTC")

  @doc "An instant on the notebook's wall clock."
  def local(%DateTime{} = at), do: DateTime.shift_zone!(at, time_zone())

  def mentions(query) do
    list(query)
    |> Enum.take(20)
    |> Enum.map(&%{id: &1.id, label: &1.title, hint: "Page"})
  end
end
