defmodule Notebook.Pages.Page do
  use Ecto.Schema
  import Ecto.Changeset

  schema "pages" do
    field :title, :string
    field :body, Kotoba.Content
    # The page's dates, picked with Koyomi: when it is due, the days it is
    # about, when its writers meet to review it, and how often to come back.
    field :due_on, :date
    field :covers, Koyomi.DateRange, storage: :string
    field :review_at, :utc_datetime
    field :revisit, Koyomi.Recurrence
    # What the page is: a text (Kotoba), a board (Hakushi, its graph in
    # `board`) or a table (Masu, its rows in page_rows).
    field :kind, :string, default: "text"
    field :board, :map
    has_many :rows, Notebook.Pages.Row
    belongs_to :author, Notebook.Accounts.User
    timestamps(type: :utc_datetime)
  end

  # The same rules go to the pickers, which disable what they refuse, and
  # to the changeset, which refuses it on the server.
  @covers_rules Koyomi.Rules.new(max_days: 366)
  @review_rules Koyomi.Rules.new(
                  min: :today,
                  disabled_weekdays: [6, 7],
                  min_time: ~T[09:00:00],
                  max_time: ~T[18:00:00],
                  time_zone: Application.compile_env(:koyomi, :time_zone, "Etc/UTC")
                )

  def covers_rules, do: @covers_rules
  def review_rules, do: @review_rules

  def changeset(page, attrs) do
    page
    |> cast(attrs, [:title, :body, :due_on, :covers, :revisit, :kind])
    |> validate_inclusion(:kind, ~w(text board table))
    |> Koyomi.Changeset.cast_datetime(attrs, :review_at, review_rules().time_zone)
    |> validate_required([:title])
    |> validate_length(:title, max: 160)
    |> Koyomi.Changeset.validate_range(:covers, @covers_rules)
    |> validate_review()
  end

  # A review already in the past stays as it is: only a new time must be
  # on a weekday from today, in working hours.
  defp validate_review(changeset) do
    if changed?(changeset, :review_at),
      do: Koyomi.Changeset.validate_datetime(changeset, :review_at, @review_rules),
      else: changeset
  end
end
