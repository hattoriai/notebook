defmodule Notebook.StorageTest do
  # The store is the node's (Storehouse's config): these run alone.
  use Notebook.DataCase, async: false
  use Oban.Testing, repo: Notebook.Repo, engine: Oban.Engines.Lite

  import Notebook.AccountsFixtures

  alias Notebook.Accounts.Scope
  alias Notebook.{FakeS3, Repo, Storage}

  setup do
    on_exit(fn ->
      Application.put_env(:storehouse, :adapter, Storehouse.Local)
      Application.delete_env(:storehouse, Storehouse.S3)
    end)

    admin = user_fixture(%{name: "Hattori Hanzo", admin: true})
    yuki = user_fixture(%{name: "Yuki Hattori"})
    %{admin: Scope.for_user(admin), yuki: Scope.for_user(yuki), bucket: FakeS3.start!()}
  end

  defp bucket_attrs(bucket, overrides \\ %{}) do
    Map.merge(
      %{
        "kind" => "bucket",
        "provider" => "other",
        "endpoint" => bucket.endpoint,
        "region" => "us-east-1",
        "bucket" => "notebook-files",
        "access_key_id" => "hanzo",
        "secret_access_key" => "no-more-swords"
      },
      overrides
    )
  end

  defp local_file(name, text) do
    key = "2026/10/#{System.unique_integer([:positive])}-#{name}"
    path = Path.join(System.tmp_dir!(), Path.basename(key))
    File.write!(path, text)
    {:ok, _url} = Storehouse.Local.put(key, path, %{content_type: "text/plain"})
    File.rm!(path)
    on_exit(fn -> Storehouse.Local.delete(key) end)
    key
  end

  test "the notebook's first person is its admin, and only an admin changes its storage", %{
    admin: admin,
    yuki: yuki,
    bucket: bucket
  } do
    assert Scope.admin?(admin)
    refute Scope.admin?(yuki)
    assert {:error, :forbidden} = Storage.save(yuki, bucket_attrs(bucket))
    assert {:error, :forbidden} = Storage.start_transfer(yuki, "copy")
    assert Storage.adapter() == Storehouse.Local
  end

  test "a bucket is tried before it is kept: one that fails says why, and nothing changes", %{
    admin: admin,
    bucket: bucket
  } do
    assert {:error, changeset} =
             Storage.save(admin, bucket_attrs(bucket, %{"endpoint" => "http://127.0.0.1:1"}))

    assert %{bucket: ["couldn't be used: " <> _reason]} = errors_on(changeset)
    assert Storage.config().kind == "local"
    assert Storage.adapter() == Storehouse.Local

    assert {:error, changeset} =
             Storage.save(admin, bucket_attrs(bucket, %{"bucket" => "", "endpoint" => ""}))

    assert %{bucket: [_], endpoint: [_]} = errors_on(changeset)
  end

  test "a bucket kept takes the new files, its secret encrypted and never shown", %{
    admin: admin,
    bucket: bucket
  } do
    assert {:ok, config} = Storage.save(admin, bucket_attrs(bucket))
    assert config.kind == "bucket" and config.secret? and config.secret_access_key == nil
    assert Storage.adapter() == Storehouse.S3
    # The probe left nothing behind.
    assert FakeS3.keys(bucket) == []

    stored = Repo.get!(Storage.Setting, "storage").value
    refute inspect(stored) =~ "no-more-swords"

    # A save without the secret keeps it.
    assert {:ok, %{secret?: true}} =
             Storage.save(admin, bucket_attrs(bucket, %{"secret_access_key" => ""}))

    path = Path.join(System.tmp_dir!(), "plan.txt")
    File.write!(path, "Fold the steel twelve times.")
    assert {:ok, file} = Storehouse.store(path)
    # The file's address is the notebook's, not the bucket's.
    assert file.url == "/uploads/kotoba/" <> file.key
    assert FakeS3.keys(bucket) == [file.key]
  end

  defp run(transfer) do
    :ok = perform_job(Storage.Transfer, %{"run" => transfer["run"], "after" => transfer["after"]})
    Storage.transfer()
  end

  test "the files of before are copied to the bucket, then removed from the disk", %{
    admin: admin,
    yuki: yuki,
    bucket: bucket
  } do
    key = local_file("letter.txt", "To the museum: no.")
    assert {:error, :nothing_to_move} = Storage.start_transfer(admin, "copy")

    {:ok, _config} = Storage.save(admin, bucket_attrs(bucket))
    assert Storage.other() == Storehouse.Local and Storage.other_files?()
    assert Storage.store_of(key) == Storehouse.Local
    assert {:error, :forbidden} = Storage.start_transfer(yuki, "copy")

    assert {:ok, %{"state" => "counting"} = transfer} = Storage.start_transfer(admin, "copy")
    assert {:error, :busy} = Storage.start_transfer(admin, "remove")

    assert %{"state" => "done", "total" => 1, "moved" => 1, "failed" => 0} = run(transfer)
    assert transfer["run"] == Storage.transfer()["run"]
    assert key in FakeS3.keys(bucket)

    {:ok, transfer} = Storage.start_transfer(admin, "remove")
    assert %{"state" => "done", "moved" => 1} = run(transfer)
    assert {:error, _missing} = Storehouse.Local.head(key)
    refute Storage.other_files?()
    assert Storage.store_of(key) == Storehouse.S3
  end

  test "a long transfer goes a slice at a time, and stops and goes on", %{
    admin: admin,
    bucket: bucket
  } do
    Application.put_env(:notebook, Storage.Transfer, slice: 0)
    on_exit(fn -> Application.delete_env(:notebook, Storage.Transfer) end)
    keys = for n <- 1..40, do: local_file("page-#{n}.txt", "Page #{n}.")
    {:ok, _config} = Storage.save(admin, bucket_attrs(bucket))

    {:ok, transfer} = Storage.start_transfer(admin, "copy")
    # One slice: the files counted, the first batch copied, the rest left to the next job.
    assert %{"state" => "running", "total" => 40, "done" => 32, "after" => cursor} = run(transfer)
    assert [_next] = all_enqueued(worker: Storage.Transfer, args: %{"after" => cursor})

    assert {:ok, %{"state" => "stopped"}} = Storage.stop_transfer(admin)
    # The job after a stop does nothing.
    assert %{"state" => "stopped", "done" => 32} = run(Storage.transfer())

    assert {:ok, %{"state" => "running"} = transfer} = Storage.resume_transfer(admin)
    # A slice ends at its deadline: the next finds nothing more.
    assert %{"state" => "running", "done" => 40} = transfer = run(transfer)

    assert %{"state" => "done", "done" => 40, "moved" => 40, "total_bytes" => bytes} =
             run(transfer)

    assert bytes > 0
    assert Enum.all?(keys, &(&1 in FakeS3.keys(bucket)))
  end

  test "the room the notebook takes: the disk, the files, the database" do
    assert %{total: total, free: free} = Storage.Usage.disk(Storage.Usage.root())
    assert total > 0 and free <= total
    assert %{count: _n, bytes: _bytes} = Storage.Usage.files(Storehouse.Local)
    assert Storage.Usage.database() > 0
    assert Storage.Usage.human(1_288_490_189) == "1.2 GB"
    assert Storage.Usage.human(512) == "512 B"
  end
end
