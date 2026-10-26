defmodule Notebook.Cardbox.Repeat do
  @moduledoc """
  A database's Repeats field: a record's rule of days (RFC 5545's `RRULE`,
  `Koyomi.Recurrence`: `FREQ=MONTHLY`, `FREQ=WEEKLY;BYDAY=FR`), and the
  record that comes back when it is done. A type of field of the
  Notebook's own (`Cardbox.FieldType`), in `config :cardbox, types:`.

  The field names its date field (`date`) and what makes a record done
  (`done`: a status, done when its choice is of the `done` group, or a
  checkbox, done when ticked). When an update makes a record done that
  was not, with a rule and a date, `next/4` gives the record that comes
  back, which `Notebook.Cardbox.after_update/4` inserts with the update:

    * the same values, on the rule's first day after the record's (a
      moment keeps its time of day);
    * not done: a status's first choice of the `todo` group, a checkbox
      unticked;
    * without the record's files: this month's invoice is not next
      month's;
    * a rule with a `COUNT` has one fewer, and the last makes no next one;
      its `UNTIL` stops it too.

  A record undone and done again comes back again: each time it becomes
  done is an occurrence.
  """
  @behaviour Cardbox.FieldType

  alias Cardbox.{Choice, Collection, Field, Type}

  @impl true
  def name, do: "repeat"

  @impl true
  def kind(_options), do: :text

  @impl true
  def check_options(options, _previous, collection) do
    with {:ok, date} <- field_of(collection, options["date"], "date", &(&1.type == "date")),
         {:ok, done} <-
           field_of(collection, options["done"], "done", &(&1.type in ~w(status checkbox))) do
      {:ok, %{"date" => date.key, "done" => done.key}}
    end
  end

  defp field_of(collection, ref, what, ok?) do
    case collection && is_binary(ref) && Collection.field(collection, ref) do
      %Field{} = field ->
        if ok?.(field),
          do: {:ok, field},
          else: {:error, "a repeat's #{what} is #{expected(what)}, got: #{inspect(field.name)}"}

      _ ->
        {:error,
         "a repeat names its #{what} field, #{expected(what)} of the database, got: #{inspect(ref)}"}
    end
  end

  defp expected("date"), do: "a date field"
  defp expected("done"), do: "a status or a checkbox field"

  @impl true
  def cast(%Koyomi.Recurrence{} = rule, _field, _opts),
    do: {:ok, Koyomi.Recurrence.to_string(rule)}

  def cast("", _field, _opts), do: {:ok, nil}

  def cast(text, _field, _opts) when is_binary(text) do
    case Koyomi.Recurrence.parse(text) do
      {:ok, rule} ->
        {:ok, Koyomi.Recurrence.to_string(rule)}

      {:error, reason} ->
        {:error, "is a rule of days, as RRULE (FREQ=MONTHLY): #{reason}, got: #{inspect(text)}"}
    end
  end

  def cast(value, _field, _opts),
    do: {:error, "is a rule of days, as RRULE (FREQ=MONTHLY), got: #{inspect(value)}"}

  @impl true
  def text(rule, _field), do: describe(rule)

  @impl true
  def json_schema(_field),
    do: %{
      "type" => "string",
      "description" =>
        "a rule of days, as RFC 5545's RRULE: FREQ=MONTHLY, FREQ=WEEKLY;BYDAY=MO, FREQ=YEARLY;COUNT=3"
    }

  @doc "A rule in words (`\"Monthly\"`), in a locale Koyomi speaks; the rule as it is if it does not parse."
  def describe(text, locale \\ "en")
  def describe(nil, _locale), do: nil

  def describe(text, locale) do
    case Koyomi.Recurrence.parse(text) do
      {:ok, rule} -> Koyomi.Recurrence.describe(rule, locale)
      {:error, _} -> text
    end
  end

  @doc """
  The values of the records that come back after an update from `before`
  to `record`: one for each Repeats field whose record became done.
  """
  def next(%Collection{fields: fields} = collection, before, record, _changed) do
    for %Field{type: "repeat"} = field <- fields,
        values = next_values(collection, field, before.data, record.data),
        do: values
  end

  defp next_values(collection, %Field{key: key, options: options}, before, data) do
    date = Collection.field(collection, options["date"])
    done = Collection.field(collection, options["done"])

    with %Field{} <- date,
         %Field{} <- done,
         true <- done?(done, data) and not done?(done, before),
         text when is_binary(text) <- data[key],
         day when is_binary(day) <- data[date.key],
         {:ok, rule} <- Koyomi.Recurrence.parse(text),
         {rule, next_day} <- following(rule, Type.load(date, day)) do
      files = for %Field{type: "file", key: file} <- collection.fields, do: file

      data
      |> Map.drop(files)
      |> Map.put(date.key, next_day)
      |> Map.put(key, Koyomi.Recurrence.to_string(rule))
      |> undone(done)
    else
      _ -> nil
    end
  end

  @doc "Whether a record's values say it is done, by a status (of the done group) or a checkbox."
  def done?(%Field{type: "checkbox", key: key}, data), do: data[key] == true

  def done?(%Field{type: "status", key: key} = field, data),
    do: match?(%{"group" => "done"}, Choice.find(Field.choices(field), data[key]))

  defp undone(values, %Field{type: "checkbox", key: key}), do: Map.delete(values, key)

  defp undone(values, %Field{type: "status", key: key} = field) do
    case Enum.find(Field.choices(field), &(&1["group"] == "todo")) do
      %{"id" => id} -> Map.put(values, key, id)
      nil -> Map.delete(values, key)
    end
  end

  # The rule's first occurrence after `start`, with the rule of the
  # occurrences left: a COUNT one fewer, none after the last.
  defp following(%{count: 1}, _start), do: nil

  defp following(rule, start) do
    case rule |> Koyomi.Recurrence.occurrences(start) |> Enum.take(2) do
      [_start, next] -> {rest(rule), next}
      _ -> nil
    end
  end

  defp rest(%{count: count} = rule) when is_integer(count), do: %{rule | count: count - 1}
  defp rest(rule), do: rule
end
