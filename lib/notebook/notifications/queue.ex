defmodule Notebook.Notifications.Queue do
  @moduledoc false
  # What notifies of a change runs here, in the order of the changes, away
  # from the process that made it. A failure is logged, and the next goes.
  use GenServer

  require Logger

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def run(fun) when is_function(fun, 0), do: GenServer.cast(__MODULE__, {:run, fun})

  # Back once what was given before this call is done.
  def settle, do: GenServer.call(__MODULE__, :settle, :infinity)

  @impl true
  def init(nil), do: {:ok, nil}

  @impl true
  def handle_cast({:run, fun}, state) do
    try do
      fun.()
    rescue
      error ->
        Logger.error("A notification failed: " <> Exception.format(:error, error, __STACKTRACE__))
    end

    {:noreply, state}
  end

  @impl true
  def handle_call(:settle, _from, state), do: {:reply, :ok, state}
end
