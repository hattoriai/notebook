defmodule Notebook.Bots.Schedule do
  @moduledoc """
  When a bot works on its own: a rule of days (RFC 5545's `RRULE`, Koyomi's)
  and a time of day in the notebook's time zone, written
  `"FREQ=WEEKLY;BYDAY=MO@09:00"`.
  """

  @doc "The rule and the time of a schedule, or `:error`."
  def parse(text) when is_binary(text) do
    with [rule, time] <- String.split(text, "@", parts: 2),
         {:ok, rule} <- Koyomi.Recurrence.parse(String.trim(rule)),
         {:ok, time} <- Time.from_iso8601(String.trim(time) <> ":00") do
      {:ok, rule, time}
    else
      _ -> :error
    end
  end

  def parse(_text), do: :error

  @doc "The schedule in words: \"Weekly on Monday, at 09:00\"."
  def describe(text) do
    case parse(text) do
      {:ok, rule, time} ->
        "#{Koyomi.Recurrence.describe(rule)}, at #{Calendar.strftime(time, "%H:%M")}"

      :error ->
        text
    end
  end

  @doc """
  The first time of the schedule after `now` (a UTC `DateTime`), as a UTC
  `DateTime`; nil when the rule has no time left.
  """
  def next(text, %DateTime{} = now, time_zone) do
    with {:ok, rule, time} <- parse(text) do
      local = DateTime.shift_zone!(now, time_zone)
      start = NaiveDateTime.new!(DateTime.to_date(local), time)

      rule
      |> Koyomi.Recurrence.occurrences(start)
      |> Stream.take(5_000)
      |> Stream.map(&to_utc(&1, time_zone))
      |> Enum.find(&(&1 && DateTime.compare(&1, now) == :gt))
    else
      :error -> nil
    end
  end

  defp to_utc(%NaiveDateTime{} = naive, time_zone) do
    case DateTime.from_naive(naive, time_zone) do
      {:ok, at} ->
        DateTime.shift_zone!(at, "Etc/UTC") |> DateTime.truncate(:second)

      {:ambiguous, at, _later} ->
        DateTime.shift_zone!(at, "Etc/UTC") |> DateTime.truncate(:second)

      {:gap, _before, at} ->
        DateTime.shift_zone!(at, "Etc/UTC") |> DateTime.truncate(:second)

      {:error, _} ->
        nil
    end
  end
end
