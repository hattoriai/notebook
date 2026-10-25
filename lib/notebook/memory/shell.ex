defmodule Notebook.Memory.Shell do
  @moduledoc """
  An agent's bash over its memory: a fresh `JustBash` for each command,
  its memory mounted at `/memories` (`Notebook.Memory.Store`), the rest a
  scratch space gone with it. No network, bounded work, time and output.
  Nothing is kept between commands but the memory itself, so an agent
  costs nothing while it does not call, however many there are.
  """

  @mount "/memories"
  @max_output 16_000

  @doc "Where the memory is mounted, and where each command starts."
  def mount, do: @mount

  @doc """
  Runs a command line for the agent: `%{"stdout", "stderr", "exit_code"}`,
  each output cut to its last 16,000 characters if longer.
  """
  def run(agent_id, command) when is_binary(command) do
    bash =
      [cwd: @mount, limits: :default]
      |> JustBash.new()
      |> JustBash.mount(@mount, Notebook.Memory.Store.new(agent_id))

    {result, _bash} = Notebook.Memory.Store.command(fn -> JustBash.exec(bash, command) end)

    %{
      "stdout" => cut(result.stdout),
      "stderr" => cut(result.stderr),
      "exit_code" => result.exit_code
    }
  end

  defp cut(text) when byte_size(text) <= @max_output, do: text

  defp cut(text),
    do:
      "[…cut: the last #{@max_output} bytes]\n" <>
        binary_part(text, byte_size(text) - @max_output, @max_output)
end
