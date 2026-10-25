defmodule Notebook.FakeS3 do
  @moduledoc """
  A bucket for the tests, at a port of this machine: what S3 does with an
  object (PUT, HEAD, GET with a range, DELETE) and a listing, kept in an
  Agent. It checks no signature.

      bucket = Notebook.FakeS3.start!()
      Notebook.FakeS3.keys(bucket)
  """
  @behaviour Plug

  import Plug.Conn

  defstruct [:agent, :endpoint]

  @doc "A bucket, served for the test that starts it."
  def start! do
    agent = ExUnit.Callbacks.start_supervised!({Agent, fn -> %{} end})

    server =
      ExUnit.Callbacks.start_supervised!(
        {Bandit,
         plug: {__MODULE__, agent}, scheme: :http, ip: :loopback, port: 0, startup_log: false}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    %__MODULE__{agent: agent, endpoint: "http://127.0.0.1:#{port}"}
  end

  @doc "The keys the bucket has."
  def keys(%__MODULE__{agent: agent}), do: agent |> Agent.get(&Map.keys/1) |> Enum.sort()

  @impl true
  def init(agent), do: agent

  @impl true
  def call(conn, agent) do
    conn = fetch_query_params(conn)

    case {conn.method, conn.path_info} do
      {"GET", [_bucket]} -> list(conn, agent)
      {method, [_bucket | key]} when key != [] -> object(method, Enum.join(key, "/"), conn, agent)
      _other -> send_resp(conn, 400, "")
    end
  end

  defp object("PUT", key, conn, agent) do
    {:ok, body, conn} = read_all(conn, "")
    type = conn |> get_req_header("content-type") |> List.first("application/octet-stream")
    Agent.update(agent, &Map.put(&1, key, {body, type}))
    conn |> put_resp_header("etag", etag(body)) |> send_resp(200, "")
  end

  defp object("DELETE", key, conn, agent) do
    Agent.update(agent, &Map.delete(&1, key))
    send_resp(conn, 204, "")
  end

  defp object(method, key, conn, agent) when method in ["GET", "HEAD"] do
    case Agent.get(agent, &Map.get(&1, key)) do
      nil ->
        send_resp(
          conn,
          404,
          "<Error><Code>NoSuchKey</Code><Message>No such key</Message></Error>"
        )

      {body, type} ->
        conn =
          conn
          |> put_resp_header("content-type", type)
          |> put_resp_header("etag", etag(body))
          |> put_resp_header("last-modified", "Sun, 25 Oct 2026 12:00:00 GMT")
          |> put_resp_header("accept-ranges", "bytes")

        case conn |> get_req_header("range") |> List.first() do
          "bytes=" <> range when method == "GET" ->
            [first, last] = String.split(range, "-")
            first = String.to_integer(first)

            last =
              min(
                if(last == "", do: byte_size(body) - 1, else: String.to_integer(last)),
                byte_size(body) - 1
              )

            conn
            |> put_resp_header("content-range", "bytes #{first}-#{last}/#{byte_size(body)}")
            |> send_resp(206, binary_part(body, first, last - first + 1))

          _whole when method == "HEAD" ->
            conn |> put_resp_header("content-length", "#{byte_size(body)}") |> send_resp(200, "")

          _whole ->
            send_resp(conn, 200, body)
        end
    end
  end

  defp object(_method, _key, conn, _agent), do: send_resp(conn, 405, "")

  defp list(conn, agent) do
    prefix = conn.query_params["prefix"] || ""
    start = conn.query_params["start-after"] || ""

    contents =
      agent
      |> Agent.get(& &1)
      |> Enum.filter(fn {key, _object} -> String.starts_with?(key, prefix) and key > start end)
      |> Enum.sort()
      |> Enum.map_join(fn {key, {body, _type}} ->
        "<Contents><Key>#{key}</Key><Size>#{byte_size(body)}</Size><LastModified>2026-10-25T12:00:00.000Z</LastModified><ETag>#{etag(body)}</ETag></Contents>"
      end)

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(
      200,
      ~s(<?xml version="1.0"?><ListBucketResult><IsTruncated>false</IsTruncated>#{contents}</ListBucketResult>)
    )
  end

  defp etag(body), do: ~s("#{Base.encode16(:crypto.hash(:md5, body), case: :lower)}")

  defp read_all(conn, acc) do
    case read_body(conn) do
      {:ok, body, conn} -> {:ok, acc <> body, conn}
      {:more, body, conn} -> read_all(conn, acc <> body)
    end
  end
end
