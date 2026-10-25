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
    # `board`), a table (Masu, its rows in page_rows) or a database (a
    # Cardbox collection of its own, Notebook.Databases).
    field :kind, :string, default: "text"
    field :board, :map
    has_many :rows, Notebook.Pages.Row
    has_many :charts, Notebook.Charts.Chart
    belongs_to :author, Notebook.Accounts.User
    # Where the page is: a space, and maybe one of its folders. An archived
    # page leaves the sidebar and the lists, and comes back when restored.
    belongs_to :space, Notebook.Spaces.Space
    belongs_to :folder, Notebook.Spaces.Folder
    field :archived_at, :utc_datetime
    # Its place among its siblings, folders and pages alike (Narabe).
    field :position, :string
    # Published (Notebook.Publishing): its public path's last word, since
    # when, and by whom.
    field :slug, :string
    field :published_at, :utc_datetime
    belongs_to :published_by, Notebook.Accounts.User
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
    |> validate_inclusion(:kind, ~w(text board table database))
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
