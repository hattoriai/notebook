defmodule Notebook.Bots.Claude do
  @moduledoc """
  The Claude API's Messages endpoint, for the bots: one request, its
  answer. Raw HTTP with Req (Elixir has no official SDK), with the key the
  admins keep (`Notebook.Bots.api_key/0`).

  `config :notebook, Notebook.Bots.Claude, req: [...]` adds Req's options
  (the tests give a `Req.Test` plug).
  """

  @url "https://api.anthropic.com/v1/messages"
  @version "2026-10-21"
  # Server-side fallbacks on a refusal, by its category (`fallbacks: "default"`).
  @fallback_beta "server-side-fallback-2026-07-01"

  @doc "Sends a Messages request; gives the answer's JSON, or why not."
  def messages(body, key) when is_map(body) and is_binary(key) do
    fallback? = Map.has_key?(body, "fallbacks")

    headers =
      [{"x-api-key", key}, {"anthropic-version", @version}] ++
        if(fallback?, do: [{"anthropic-beta", @fallback_beta}], else: [])

    options =
      Keyword.merge(
        [url: @url, json: body, headers: headers, receive_timeout: 600_000, retry: :transient],
        Keyword.get(Application.get_env(:notebook, __MODULE__, []), :req, [])
      )

    case Req.post(options) do
      {:ok, %Req.Response{status: 200, body: %{} = answer}} ->
        {:ok, answer}

      {:ok, %Req.Response{status: status, body: %{"error" => %{"message" => message}}}} ->
        {:error, "The Claude API answered #{status}: #{message}"}

      {:ok, %Req.Response{status: status}} ->
        {:error, "The Claude API answered #{status}."}

      {:error, exception} ->
        {:error, "The Claude API could not be reached: #{Exception.message(exception)}"}
    end
  end

  @doc "Whether a model takes server-side fallbacks (Haiku has none)."
  def fallbacks?(model), do: model != "claude-haiku-5-5"
end
