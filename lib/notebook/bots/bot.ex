defmodule Notebook.Bots.Bot do
  @moduledoc """
  A bot of the notebook: its name and what it is told (`instructions`),
  the model it thinks with, the tools it may use (by group,
  `Notebook.Bots.tool_groups/0`), what wakes it (a mention or a task
  handed to it, a new page, a visitor's question on a published page, a
  schedule), and the most it may spend a month. It works with the rights
  of its account (`user`), a member of the spaces it was added to.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @models ~w(claude-opus-5-5 claude-sonnet-5-5 claude-haiku-5-5 claude-fable-5-1)
  @efforts ~w(low medium high)

  schema "bots" do
    belongs_to :user, Notebook.Accounts.User
    field :name, :string
    field :instructions, :string, default: ""
    field :model, :string, default: "claude-opus-5-5"
    field :effort, :string, default: "medium"
    field :tools, {:array, :string}, default: ["read", "comment"]
    field :on_mention, :boolean, default: true
    field :on_new_page, :boolean, default: false
    field :public, :boolean, default: false
    field :schedule, :string
    field :schedule_task, :string
    field :next_run_at, :utc_datetime
    field :monthly_budget_cents, :integer, default: 500
    field :enabled, :boolean, default: true
    has_many :runs, Notebook.Bots.Run
    timestamps(type: :utc_datetime)
  end

  @doc "The models a bot may think with, the first the default."
  def models, do: @models

  @doc "How hard a bot thinks."
  def efforts, do: @efforts

  @doc false
  def changeset(bot, attrs) do
    bot
    |> cast(attrs, [
      :name,
      :instructions,
      :model,
      :effort,
      :tools,
      :on_mention,
      :on_new_page,
      :public,
      :schedule,
      :schedule_task,
      :monthly_budget_cents,
      :enabled
    ])
    |> update_change(:name, &String.trim/1)
    |> update_change(:schedule, &blank/1)
    |> update_change(:schedule_task, &blank/1)
    |> validate_required([:name, :model, :effort])
    |> validate_length(:name, max: 60)
    |> validate_length(:instructions, max: 20_000)
    |> validate_length(:schedule_task, max: 4_000)
    |> validate_inclusion(:model, @models)
    |> validate_inclusion(:effort, @efforts)
    |> validate_number(:monthly_budget_cents, greater_than_or_equal_to: 0, less_than: 1_000_000)
    |> validate_subset(:tools, Notebook.Bots.tool_group_names())
    |> validate_schedule()
  end

  defp blank(nil), do: nil

  defp blank(text) do
    case String.trim(text) do
      "" -> nil
      text -> text
    end
  end

  # A schedule is a rule of days and a time: "FREQ=WEEKLY;BYDAY=MO" at a
  # time of day (`HH:MM`), written "FREQ=WEEKLY;BYDAY=MO@09:00"; and a task
  # to do then.
  defp validate_schedule(changeset) do
    case get_field(changeset, :schedule) do
      nil ->
        changeset

      schedule ->
        cond do
          Notebook.Bots.Schedule.parse(schedule) == :error ->
            add_error(changeset, :schedule, "is a rule and a time: FREQ=DAILY@09:00")

          get_field(changeset, :schedule_task) in [nil, ""] ->
            add_error(changeset, :schedule_task, "says what to do at those times")

          true ->
            changeset
        end
    end
  end
end
