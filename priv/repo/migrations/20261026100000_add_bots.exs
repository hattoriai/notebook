defmodule Notebook.Repo.Migrations.AddBots do
  use Ecto.Migration

  # The notebook's own bots (Notebook.Bots): each one an account no one
  # signs in to, a member of the spaces it works in, with what it is told,
  # the tools it may use, what wakes it and how much it may spend; and the
  # runs it made.
  def change do
    alter table(:users) do
      add :bot, :boolean, null: false, default: false
    end

    create table(:bots) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :instructions, :text, null: false, default: ""
      add :model, :string, null: false
      add :effort, :string, null: false, default: "medium"
      add :tools, {:array, :string}, null: false, default: []
      add :on_mention, :boolean, null: false, default: true
      add :on_new_page, :boolean, null: false, default: false
      add :public, :boolean, null: false, default: false
      add :schedule, :string
      add :schedule_task, :text
      add :next_run_at, :utc_datetime
      add :monthly_budget_cents, :integer, null: false, default: 500
      add :enabled, :boolean, null: false, default: true
      timestamps(type: :utc_datetime)
    end

    create unique_index(:bots, [:user_id])
    create index(:bots, [:next_run_at])

    create table(:bot_runs) do
      add :bot_id, references(:bots, on_delete: :delete_all), null: false
      add :trigger, :string, null: false
      add :room, :string
      add :status, :string, null: false
      add :steps, :integer, null: false, default: 0
      add :input_tokens, :integer, null: false, default: 0
      add :output_tokens, :integer, null: false, default: 0
      add :cost_micros, :integer, null: false, default: 0
      add :summary, :text
      add :error, :text
      timestamps(type: :utc_datetime)
    end

    create index(:bot_runs, [:bot_id, :inserted_at])
  end
end
