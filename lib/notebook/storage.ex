defmodule Notebook.Storage do
  @moduledoc """
  Where the notebook keeps its files (the pages' images and attachments,
  with Storehouse): on this server's disk, or in a bucket of any store
  that speaks S3's API (Amazon S3, Cloudflare R2, Tigris, Backblaze B2,
  MinIO, or a drive behind `rclone serve s3`). Its admins choose it in
  the notebook's settings; nothing to deploy again.

  The files keep their addresses (`/uploads/kotoba/<key>`) whichever
  store has them: the pages keep those, and the notebook serves each
  file from where it is (`NotebookWeb.Plugs.Files`), behind who may read
  it. So a notebook moves to a bucket, or back, without a page changing:
  new files go to the store chosen, the others are copied to it as a job
  (`start_transfer/2`), and until then are served from where they were.

  The bucket's secret is one of the notebook's secrets
  (`Notebook.Secrets`), encrypted by `Notebook.Vault`.
  """
  import Ecto.Changeset, except: [change: 2]

  alias Notebook.Accounts.Scope
  alias Notebook.Repo
  alias Notebook.Storage.{Config, Setting}

  @topic "storage"
  # The bucket's secret is the notebook's (Notebook.Secrets), not the settings'.
  @secret "storage.secret_access_key"
  @prefix "/uploads/kotoba"

  @providers [
    %{id: "aws", name: "Amazon S3", endpoint: nil, region: "us-east-1"},
    %{
      id: "r2",
      name: "Cloudflare R2",
      endpoint: "https://<account id>.r2.cloudflarestorage.com",
      region: "auto"
    },
    %{id: "tigris", name: "Tigris", endpoint: "https://t3.storage.dev", region: "auto"},
    %{
      id: "b2",
      name: "Backblaze B2",
      endpoint: "https://s3.<region>.backblazeb2.com",
      region: "us-west-004"
    },
    %{id: "other", name: "Another (MinIO, Spaces, rclone…)", endpoint: "https://", region: ""}
  ]

  @doc "The stores that speak S3's API, as the form offers them: their endpoints' shapes."
  def providers, do: @providers

  @doc "Where the files are kept now (a `Config`, its secret never in it)."
  def config do
    stored = stored()
    %{load(stored) | secret_access_key: nil, secret?: secret(stored) != nil}
  end

  @doc "A change of where the files are, for the form."
  def change(%Config{} = config, attrs \\ %{}) do
    config
    |> cast(attrs, [
      :kind,
      :provider,
      :endpoint,
      :region,
      :bucket,
      :access_key_id,
      :secret_access_key,
      :serve
    ])
    |> validate_inclusion(:kind, ~w(local bucket))
    |> validate_inclusion(:serve, ~w(app redirect))
    |> validate_inclusion(:provider, Enum.map(@providers, & &1.id))
    |> update_change(:endpoint, &String.trim/1)
    |> update_change(:bucket, &String.trim/1)
    |> update_change(:region, &String.trim/1)
    |> update_change(:access_key_id, &String.trim/1)
    |> validate_bucket()
  end

  defp validate_bucket(changeset) do
    if get_field(changeset, :kind) == "bucket" do
      changeset
      |> validate_required([:bucket, :region, :access_key_id],
        message: "is needed for a bucket"
      )
      |> validate_secret()
      |> validate_endpoint()
    else
      changeset
    end
  end

  defp validate_secret(changeset) do
    if get_field(changeset, :secret?) or present?(get_change(changeset, :secret_access_key)),
      do: changeset,
      else: add_error(changeset, :secret_access_key, "is needed for a bucket")
  end

  defp validate_endpoint(changeset) do
    case {get_field(changeset, :provider), get_field(changeset, :endpoint)} do
      {"aws", endpoint} when endpoint in [nil, ""] ->
        changeset

      {_provider, endpoint} when endpoint in [nil, ""] ->
        add_error(changeset, :endpoint, "is needed for this store")

      {_provider, endpoint} ->
        case URI.parse(endpoint) do
          %URI{scheme: scheme, host: host}
          when scheme in ["http", "https"] and host not in [nil, ""] ->
            if String.contains?(endpoint, "<"),
              do: add_error(changeset, :endpoint, "has a part to fill in"),
              else: changeset

          _other ->
            add_error(changeset, :endpoint, "must be an address, https://…")
        end
    end
  end

  @doc """
  Keeps the files where `attrs` say, for an admin: a bucket is tried
  first (a small file written, read and removed), and kept only if that
  works. The notebook's new files go there at once.
  """
  def save(%Scope{} = scope, attrs) do
    with :ok <- admin(scope),
         stored = stored(),
         changeset =
           change(%{load(stored) | secret_access_key: nil, secret?: secret(stored) != nil}, attrs),
         {:ok, config} <- apply_action(changeset, :save),
         config = %{config | secret_access_key: config.secret_access_key || secret(stored)},
         :ok <- try_bucket(config, changeset) do
      if present?(attrs_secret(attrs)),
        do: Notebook.Secrets.put(@secret, config.secret_access_key)

      value =
        stored
        |> Map.merge(dump(config))
        |> Map.put("saved_by", scope.user.id)

      Repo.insert!(%Setting{key: "storage", value: value},
        on_conflict: [set: [value: value, updated_at: DateTime.utc_now(:second)]],
        conflict_target: :key
      )

      apply()
      broadcast({:storage, :saved})
      {:ok, config()}
    end
  end

  defp try_bucket(%Config{kind: "bucket"} = config, changeset) do
    case probe(config) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error,
         changeset
         |> add_error(:bucket, "couldn't be used: " <> describe(reason))
         |> Map.put(:action, :save)}
    end
  end

  defp try_bucket(_config, _changeset), do: :ok

  @doc """
  Whether the bucket of `config` takes a file, gives it back and lets it
  be removed: `:ok`, or the reason it does not.
  """
  def probe(%Config{} = config) do
    c = s3(config)
    key = "notebook/probe-#{System.unique_integer([:positive])}.txt"
    path = Path.join(System.tmp_dir!(), Path.basename(key))
    File.write!(path, "Notebook checks it may keep its files here.\n")

    try do
      with {:ok, _url} <- Storehouse.S3.put(c, key, path, %{content_type: "text/plain"}),
           {:ok, _head} <- Storehouse.S3.head(c, key) do
        Storehouse.S3.delete(c, key)
      end
    rescue
      error -> {:error, Exception.message(error)}
    after
      File.rm(path)
    end
  end

  @doc "A store's refusal, in words."
  def describe({:s3, status, body}) when is_binary(body) do
    code = Regex.run(~r{<Code>(.*?)</Code>}s, body, capture: :all_but_first)
    message = Regex.run(~r{<Message>(.*?)</Message>}s, body, capture: :all_but_first)

    case {code, message} do
      {[code], [message]} -> "#{code}: #{message} (#{status})"
      {[code], nil} -> "#{code} (#{status})"
      _none -> "the store answered #{status}"
    end
  end

  def describe({:s3, status, _body}), do: "the store answered #{status}"
  def describe(%{__exception__: true} = error), do: Exception.message(error)
  def describe(reason) when is_binary(reason), do: reason
  def describe(:nxdomain), do: "no such address"
  def describe(:econnrefused), do: "nothing answers at that address"
  def describe(:timeout), do: "the store took too long to answer"
  def describe(reason), do: inspect(reason)

  @doc """
  Makes the store kept the notebook's: Storehouse's (and so Kotoba's)
  adapter, and where it finds the bucket's settings (`s3_config/0`). At
  boot, and on each save.
  """
  def apply do
    stored = stored()
    config = load(stored)

    # The bucket's config, the secret with it, given each time Storehouse
    # needs it (`s3_config/0`): the secret never sits in the environment.
    Application.put_env(:storehouse, Storehouse.S3, {__MODULE__, :s3_config, []})

    adapter =
      cond do
        config.kind != "bucket" ->
          Storehouse.Local

        bucket?(config, stored) ->
          Storehouse.S3

        # A bucket whose secret no longer opens (its vault key is gone):
        # the disk, until an admin gives the secret again.
        true ->
          require Logger

          Logger.warning(
            "Notebook.Storage: the bucket's secret can't be read; new files go to this disk"
          )

          Storehouse.Local
      end

    Application.put_env(:storehouse, :adapter, adapter)
    :ok
  end

  @doc """
  The bucket's config as `Storehouse.S3` takes it, its secret from the
  vault (`Notebook.Secrets`): Storehouse asks for it each time it needs
  it. Empty with no bucket kept.
  """
  def s3_config do
    stored = stored()
    config = load(stored)

    if bucket?(config, stored),
      do: s3(%{config | secret_access_key: secret(stored)}),
      else: []
  end

  @doc false
  # At boot, before the endpoint serves: the store kept, or the disk.
  def child_spec(_opts),
    do: %{id: __MODULE__, start: {__MODULE__, :start_link, []}, restart: :temporary}

  @doc false
  def start_link do
    apply()
    :ignore
  rescue
    error ->
      require Logger

      Logger.warning(
        "Notebook.Storage: keeping the files on this disk: #{Exception.message(error)}"
      )

      :ignore
  end

  @doc "The store the notebook's new files go to."
  def adapter, do: Storehouse.adapter()

  @doc """
  The other store that has files, if there is one: this disk, with a
  bucket chosen; a bucket kept, with the disk chosen. Its files are
  served until they are copied (`start_transfer/2`).
  """
  def other do
    stored = stored()
    config = load(stored)

    cond do
      config.kind == "bucket" -> Storehouse.Local
      bucket?(config, stored) -> Storehouse.S3
      true -> nil
    end
  end

  @doc """
  The store that has the file with `key`: the disk if the file is on it
  (a look at the disk, nothing asked of a bucket), else the bucket.
  """
  def store_of(key) do
    case {adapter(), other()} do
      {Storehouse.Local, nil} ->
        Storehouse.Local

      {active, other} ->
        local = if active == Storehouse.Local, do: active, else: other
        bucket = if active == Storehouse.Local, do: other, else: active

        case Storehouse.Local.head(key) do
          {:ok, _head} -> local
          _missing -> bucket
        end
    end
  end

  @doc "How the bucket's files are served: `\"app\"` or `\"redirect\"`."
  def serve, do: Map.get(stored(), "serve", "app")

  @doc "The address of the files, the same in every store."
  def prefix, do: @prefix

  @doc """
  Starts moving the files of the other store (`other/0`) to the
  notebook's, for an admin: `"copy"` copies each (a file there already is
  skipped), `"remove"` removes from the other store each file the
  notebook's has, the same size. It runs as jobs, a slice at a time
  (`Notebook.Storage.Transfer`), so that it may take hours and outlast a
  restart; `transfer/0` is where it is.
  """
  def start_transfer(%Scope{} = scope, action) when action in ["copy", "remove"] do
    with :ok <- admin(scope),
         :ok <- idle(),
         from when not is_nil(from) <- other() do
      now = DateTime.utc_now(:second) |> DateTime.to_iso8601()

      put_transfer(%{
        "run" => System.unique_integer([:positive]),
        "action" => action,
        "from" => inspect(from),
        "to" => inspect(adapter()),
        "state" => "counting",
        "total" => nil,
        "total_bytes" => nil,
        "done" => 0,
        "done_bytes" => 0,
        "moved" => 0,
        "skipped" => 0,
        "failed" => 0,
        "errors" => [],
        "after" => nil,
        "started_at" => now,
        "finished_at" => nil
      })
      |> Notebook.Storage.Transfer.enqueue()
    else
      nil -> {:error, :nothing_to_move}
      error -> error
    end
  end

  @doc "Goes on with a transfer stopped, from where it was, for an admin."
  def resume_transfer(%Scope{} = scope) do
    with :ok <- admin(scope),
         %{"state" => "stopped"} = transfer <- transfer() || {:error, :nothing_to_move} do
      transfer
      |> Map.merge(%{"state" => if(transfer["total"], do: "running", else: "counting")})
      |> put_transfer()
      |> Notebook.Storage.Transfer.enqueue()
    end
  end

  @doc "Stops the transfer at its next files, for an admin: it can go on later."
  def stop_transfer(%Scope{} = scope) do
    with :ok <- admin(scope),
         %{"state" => state} = transfer when state in ["counting", "running"] <-
           transfer() || {:error, :nothing_to_move} do
      {:ok, put_transfer(%{transfer | "state" => "stopped"})}
    end
  end

  defp idle do
    case transfer() do
      %{"state" => state} when state in ["counting", "running"] -> {:error, :busy}
      _idle -> :ok
    end
  end

  @doc """
  The transfer of the files, the last one: its action, its state
  (`"counting"`, `"running"`, `"stopped"`, `"done"`), how many files and
  bytes it has and has done, those moved, skipped and failed, the first
  errors, and when it started and finished. Nil before the first.
  """
  def transfer do
    case Repo.get(Setting, "transfer") do
      %Setting{value: value} when value != %{} -> value
      _none -> nil
    end
  end

  @doc false
  def put_transfer(transfer) do
    transfer = Map.put(transfer, "updated_at", DateTime.utc_now(:second) |> DateTime.to_iso8601())

    Repo.insert!(%Setting{key: "transfer", value: transfer},
      on_conflict: [set: [value: transfer, updated_at: DateTime.utc_now(:second)]],
      conflict_target: :key
    )

    broadcast({:storage, :transfer, transfer})
    transfer
  end

  @doc "Whether the other store (`other/0`) has any file."
  def other_files? do
    with store when not is_nil(store) <- other(),
         {:ok, entries} <- Storehouse.list("", adapter: store) do
      Enum.any?(Stream.take(entries, 1))
    else
      _none -> false
    end
  rescue
    _error -> false
  end

  @doc """
  Tells of the storage's changes: `{:storage, :saved}`, and
  `{:storage, :transfer, transfer}` as the files move.
  """
  def subscribe, do: Phoenix.PubSub.subscribe(Notebook.PubSub, @topic)

  @doc false
  def broadcast(message), do: Phoenix.PubSub.broadcast(Notebook.PubSub, @topic, message)

  defp admin(scope), do: if(Scope.admin?(scope), do: :ok, else: {:error, :forbidden})

  defp stored do
    case Repo.get(Setting, "storage") do
      %Setting{value: value} -> value
      nil -> %{}
    end
  end

  @fields ~w(kind provider endpoint region bucket access_key_id serve)

  defp load(stored) do
    Enum.reduce(@fields, %Config{}, fn field, config ->
      case Map.fetch(stored, field) do
        {:ok, value} when not is_nil(value) ->
          Map.put(config, String.to_existing_atom(field), value)

        _missing ->
          config
      end
    end)
  end

  defp dump(%Config{} = config) do
    Map.new(@fields, &{&1, Map.fetch!(config, String.to_existing_atom(&1))})
  end

  defp bucket?(config, stored),
    do: present?(config.bucket) and present?(config.access_key_id) and secret(stored) != nil

  defp s3(%Config{} = config) do
    [
      bucket: config.bucket,
      region: config.region,
      access_key_id: config.access_key_id,
      secret_access_key: config.secret_access_key,
      # The files' addresses are the notebook's own, whichever store has them.
      public_url: @prefix
    ]
    |> then(fn opts ->
      if present?(config.endpoint), do: [{:endpoint, config.endpoint} | opts], else: opts
    end)
  end

  defp secret(_stored), do: Notebook.Secrets.get(@secret)

  defp attrs_secret(attrs), do: attrs["secret_access_key"] || attrs[:secret_access_key]

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
