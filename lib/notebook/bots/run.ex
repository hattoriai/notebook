defmodule Notebook.Bots.Run do
  @moduledoc """
  One time a bot worked: what woke it, in which room, how it ended
  (`running`, `done`, `failed`, `stopped`: over its budget or its steps,
  or paused), its steps, the tokens it read and wrote, and what that cost
  (millionths of a dollar, as the model's list prices say).
  """
  use Ecto.Schema

  schema "bot_runs" do
    belongs_to :bot, Notebook.Bots.Bot
    field :trigger, :string
    field :room, :string
    field :status, :string, default: "running"
    field :steps, :integer, default: 0
    field :input_tokens, :integer, default: 0
    field :output_tokens, :integer, default: 0
    field :cost_micros, :integer, default: 0
    field :summary, :string
    field :error, :string
    timestamps(type: :utc_datetime)
  end
end
