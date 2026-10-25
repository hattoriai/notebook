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
  (`copy/1`), and until then are served from where they were.

  The bucket's secret is kept encrypted with the notebook's
  `secret_key_base`.
  """
  import Ecto.Changeset, except: [change: 2]

  alias Notebook.Accounts.Scope
  alias Notebook.Repo
  alias Notebook.Storage.{Config, Setting}

  @topic "storage"
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
  adapter, and the bucket's settings when there is one. At boot, and on
  each save.
  """
  def apply do
    stored = stored()
    config = load(stored)

    if bucket?(config, stored) do
      Application.put_env(
        :storehouse,
        Storehouse.S3,
        s3(%{config | secret_access_key: secret(stored)})
      )
    end

    adapter =
      cond do
        config.kind != "bucket" ->
          Storehouse.Local

        bucket?(config, stored) ->
          Storehouse.S3

        # A bucket whose secret no longer opens (`secret_key_base` changed):
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
  served until they are copied (`copy/1`).
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
  Copies the files of the other store (`other/0`) to the notebook's, as a
  job, for an admin. Files already there are skipped, so it can run again.
  """
  def copy(%Scope{} = scope) do
    with :ok <- admin(scope) do
      case other() do
        nil ->
          {:error, :nothing_to_copy}

        _store ->
          %{} |> Notebook.Storage.Copy.new() |> Oban.insert()
      end
    end
  end

  @doc """
  Removes from the other store (`other/0`) the files the notebook's store
  has now, as a job, for an admin: after a copy, the room they took.
  """
  def prune(%Scope{} = scope) do
    with :ok <- admin(scope) do
      if other(),
        do: %{} |> Notebook.Storage.Prune.new() |> Oban.insert(),
        else: {:error, :nothing_to_copy}
    end
  end

  @doc """
  Every file of `store`, as `Storehouse.copy_prefix/2` lists them: its own
  `list/1` of `""`, the keys it gives checked (`Storehouse.list/2` takes
  no empty prefix).
  """
  def all(store) do
    with {:ok, entries} <- store.list(""),
         do: {:ok, Stream.filter(entries, &Storehouse.valid_key?(&1.key))}
  end

  @doc "Whether the other store (`other/0`) has any file."
  def other_files? do
    with store when not is_nil(store) <- other(),
         {:ok, entries} <- all(store) do
      Enum.any?(Stream.take(entries, 1))
    else
      _none -> false
    end
  rescue
    _error -> false
  end

  @doc false
  def pruned(removed) do
    value = Map.update(stored(), "last_copy", nil, &(&1 && Map.put(&1, "removed", removed)))

    Repo.insert!(%Setting{key: "storage", value: value},
      on_conflict: [set: [value: value, updated_at: DateTime.utc_now(:second)]],
      conflict_target: :key
    )

    broadcast({:storage, :pruned, removed})
  end

  @doc "The last copy's result: `%{\"copied\" => n, \"skipped\" => n, \"failed\" => n, \"at\" => …}`, or nil."
  def last_copy, do: Map.get(stored(), "last_copy")

  @doc false
  def copied(result) do
    value = Map.put(stored(), "last_copy", result)

    Repo.insert!(%Setting{key: "storage", value: value},
      on_conflict: [set: [value: value, updated_at: DateTime.utc_now(:second)]],
      conflict_target: :key
    )

    broadcast({:storage, :copied, result})
  end

  @doc "Tells of the storage's changes: `{:storage, :saved}`, `{:storage, :copying, n}`, `{:storage, :copied, result}`, `{:storage, :pruned, n}`."
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
    fields = Map.new(@fields, &{&1, Map.fetch!(config, String.to_existing_atom(&1))})

    case config.secret_access_key do
      secret when is_binary(secret) and secret != "" -> Map.put(fields, "secret", encrypt(secret))
      _none -> fields
    end
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

  defp secret(%{"secret" => token}) when is_binary(token) do
    case Plug.Crypto.decrypt(secret_key_base(), "notebook storage", token, max_age: :infinity) do
      {:ok, secret} -> secret
      {:error, _reason} -> nil
    end
  end

  defp secret(_stored), do: nil

  defp encrypt(secret), do: Plug.Crypto.encrypt(secret_key_base(), "notebook storage", secret)

  defp secret_key_base,
    do: Application.fetch_env!(:notebook, NotebookWeb.Endpoint)[:secret_key_base]

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
