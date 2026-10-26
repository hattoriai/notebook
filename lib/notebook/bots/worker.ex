defmodule Notebook.Bots.Worker do
  @moduledoc """
  A bot's run, as a job: once, whatever it gives. A bot that is off, past
  its month's budget or without the Claude API's key does not run; its run
  says why. An item of its inbox is read as it starts.
  """
  use Oban.Worker, queue: :bots, max_attempts: 1

  alias Notebook.Bots
  alias Notebook.Bots.{Bot, Run, Runner}
  alias Notebook.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"bot_id" => id, "trigger" => trigger}}) do
    with %Bot{} = bot <- Repo.get(Bot, id) |> Repo.preload(:user) do
      read(bot, trigger)
      run = Repo.insert!(%Run{bot_id: bot.id, trigger: kind(trigger), status: "running"})

      cond do
        not bot.enabled ->
          finish(run, "stopped", "The bot is off.")

        Bots.over_budget?(bot) ->
          finish(run, "stopped", "It spent its month's budget.")

        true ->
          trigger =
            if trigger["kind"] == "schedule", do: %{"kind" => "schedule_task"}, else: trigger

          {run, words} = Runner.run(bot, trigger, run)
          answer(trigger, words, run)
      end
    end

    :ok
  end

  defp kind(%{"kind" => "inbox", "item" => %{"name" => name}}), do: name
  defp kind(%{"kind" => kind}), do: kind

  defp read(bot, %{"kind" => "inbox", "item" => %{"id" => item}}),
    do: Issho.Inbox.mark_read(Notebook.Issho, Bots.key(bot), [item])

  defp read(bot, %{"kind" => "visitor", "item_id" => item}) when is_binary(item),
    do: Issho.Inbox.mark_read(Notebook.Issho, Bots.key(bot), [item])

  defp read(_bot, _trigger), do: :ok

  defp finish(run, status, error),
    do: run |> Ecto.Changeset.change(status: status, error: error) |> Repo.update!()

  # A visitor's question: the answer goes to the page they asked on.
  defp answer(%{"kind" => "visitor", "request" => request}, words, run) do
    Phoenix.PubSub.broadcast(
      Notebook.PubSub,
      "bots:answer:" <> request,
      {:bot_answer, request, words || fallback(run)}
    )
  end

  defp answer(_trigger, _words, _run), do: :ok

  defp fallback(%Run{status: "failed"}), do: "Sorry, I could not answer that now."
  defp fallback(_run), do: "Sorry, I have no answer to that."
end

defmodule Notebook.Bots.Scheduler do
  @moduledoc "Each minute, the bots whose schedule has come (Oban's cron)."
  use Oban.Worker, queue: :bots, max_attempts: 1

  @impl Oban.Worker
  def perform(_job) do
    Notebook.Bots.due()
    :ok
  end
end
