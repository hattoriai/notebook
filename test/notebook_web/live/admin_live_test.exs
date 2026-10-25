defmodule NotebookWeb.AdminLiveTest do
  # The store is the node's (Storehouse's config): these run alone.
  use NotebookWeb.ConnCase, async: false
  use Oban.Testing, repo: Notebook.Repo, engine: Oban.Engines.Lite

  import Phoenix.LiveViewTest
  import Notebook.AccountsFixtures

  alias Notebook.{FakeS3, Storage}

  setup do
    on_exit(fn ->
      Application.put_env(:storehouse, :adapter, Storehouse.Local)
      Application.delete_env(:storehouse, Storehouse.S3)
    end)

    %{
      admin: user_fixture(%{name: "Hattori Hanzo", admin: true}),
      yuki: user_fixture(%{name: "Yuki Hattori"}),
      bucket: FakeS3.start!()
    }
  end

  defp local_file(text) do
    key = "2026/10/#{System.unique_integer([:positive])}-plan.txt"
    path = Path.join(System.tmp_dir!(), Path.basename(key))
    File.write!(path, text)
    {:ok, _url} = Storehouse.Local.put(key, path, %{content_type: "text/plain"})
    on_exit(fn -> Storehouse.Local.delete(key) end)
    key
  end

  test "only an admin sees the notebook's settings", %{conn: conn, yuki: yuki} do
    assert {:error, {:live_redirect, %{to: "/"}}} = live(log_in_user(conn, yuki), ~p"/admin")
  end

  test "an admin moves the files to a bucket, and copies those of before", %{
    conn: conn,
    admin: admin,
    bucket: bucket
  } do
    key = local_file("Fold the steel twelve times.")
    {:ok, view, html} = live(log_in_user(conn, admin), ~p"/admin")
    assert html =~ "Where files are kept"
    assert html =~ "On this server"
    refute has_element?(view, "#storage-copy")

    view |> form("#storage-form", storage: %{kind: "bucket"}) |> render_change()
    assert has_element?(view, ".storage-bucket")
    refute has_element?(view, "#storage_endpoint")

    # Another store than Amazon's asks for its endpoint, and gives its region.
    view |> form("#storage-form", storage: %{kind: "bucket", provider: "r2"}) |> render_change()
    assert has_element?(view, "#storage_endpoint[placeholder*='r2.cloudflarestorage.com']")
    assert has_element?(view, "#storage_region[value=auto]")

    view
    |> form("#storage-form", storage: %{kind: "bucket", provider: "other"})
    |> render_change()

    view
    |> form("#storage-form",
      storage: %{
        kind: "bucket",
        provider: "other",
        endpoint: bucket.endpoint,
        bucket: "notebook-files",
        region: "us-east-1",
        access_key_id: "hanzo",
        secret_access_key: "no-more-swords"
      }
    )
    |> render_submit()

    assert render(view) =~ "New files go to the bucket notebook-files now."
    assert has_element?(view, ".storage-now", "In the bucket notebook-files")
    assert has_element?(view, "#storage-copy", "Files from before are still on this server")

    view |> element("#storage-copy-start") |> render_click()
    assert_enqueued(worker: Storage.Copy)
    assert :ok = perform_job(Storage.Copy, %{})
    assert key in FakeS3.keys(bucket)
    assert has_element?(view, "#storage-prune")
  end

  test "a file is served from the store that has it, to those who may read it", %{
    conn: conn,
    admin: admin,
    bucket: bucket
  } do
    key = local_file("Fold the steel twelve times.")
    signed_in = log_in_user(conn, admin)
    assert get(signed_in, "/uploads/kotoba/" <> key).resp_body == "Fold the steel twelve times."

    {:ok, _config} =
      Storage.save(Notebook.Accounts.Scope.for_user(admin), %{
        "kind" => "bucket",
        "provider" => "other",
        "endpoint" => bucket.endpoint,
        "bucket" => "notebook-files",
        "region" => "us-east-1",
        "access_key_id" => "hanzo",
        "secret_access_key" => "no-more-swords"
      })

    :ok = perform_job(Storage.Copy, %{})
    :ok = perform_job(Storage.Prune, %{})

    # On the bucket only now, at the same address.
    response = get(log_in_user(build_conn(), admin), "/uploads/kotoba/" <> key)
    assert response.status == 200
    assert response.resp_body == "Fold the steel twelve times."
    assert get(build_conn(), "/uploads/kotoba/" <> key).status == 404
  end
end
