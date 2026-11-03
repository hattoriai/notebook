defmodule Notebook.PublishingTest do
  # SQLite takes one writer at a time: these write a lot, so they run alone.
  use Notebook.DataCase, async: false

  import Notebook.AccountsFixtures

  alias Notebook.Accounts.Scope
  alias Notebook.{Pages, Publishing, Spaces}

  setup do
    hanzo = user_fixture(%{name: "Hattori Hanzo"})
    yuki = user_fixture(%{name: "Yuki Hattori"})
    scope = Scope.for_user(hanzo)
    {:ok, forge} = Spaces.create_team(scope, %{name: "The forge"})
    {:ok, _} = Spaces.add_member(scope, forge, yuki, "viewer")
    {:ok, journal} = Spaces.create_folder(scope, forge, %{name: "Journal"})
    {:ok, kotoba} = Pages.create(scope, %{"title" => "Kotoba", "space_id" => forge.id})

    {:ok, day} =
      Pages.create(scope, %{
        "title" => "Day one without steel",
        "space_id" => forge.id,
        "folder_id" => journal.id
      })

    on_exit(fn -> Application.delete_env(:notebook, :publishing) end)
    %{hanzo: hanzo, yuki: yuki, scope: scope, journal: journal, kotoba: kotoba, day: day}
  end

  test "a person has a handle from their name, and no path of the notebook", %{hanzo: hanzo} do
    assert hanzo.handle == "hanzo"
    assert Publishing.free_handle("Hattori Hanzo") == "hanzo-2"
    assert Publishing.free_handle("Ana Inbox") == "person"
  end

  test "no handle takes the settings' addresses", %{hanzo: hanzo} do
    for word <- ~w(account notebook) do
      assert word in Publishing.reserved()
      changeset = Notebook.Accounts.User.handle_changeset(hanzo, %{handle: word})
      assert "is a path of the notebook" in errors_on(changeset).handle
    end
  end

  test "its editors publish a page under a slug, at its publisher's path", %{
    scope: scope,
    yuki: yuki,
    kotoba: kotoba
  } do
    assert {:error, _} = Publishing.publish(Scope.for_user(yuki), kotoba)

    {:ok, page} = Publishing.publish(scope, kotoba)
    assert page.slug == "kotoba"
    assert Publishing.url(page) == NotebookWeb.Endpoint.url() <> "/the-forge/kotoba"
    assert {:page, %{id: id}} = Publishing.resolve(["the-forge", "kotoba"])
    assert id == kotoba.id

    {:ok, page} = Publishing.unpublish(scope, page)
    assert page.slug == "kotoba"
    assert Publishing.resolve(["the-forge", "kotoba"]) == :not_found
  end

  test "a slug is free, and no path of the notebook", %{scope: scope, kotoba: kotoba, day: day} do
    {:ok, _} = Publishing.publish(scope, kotoba, "kotoba")

    assert {:error, "Another page or folder is published as “kotoba”."} =
             Publishing.publish(scope, day, "kotoba")

    assert {:error, "“inbox” is a path of the notebook: choose another."} =
             Publishing.publish(scope, day, "inbox")

    assert {:error, "A slug is lowercase letters, digits and dashes."} =
             Publishing.publish(scope, day, "Day One")

    assert Publishing.suggest_slug(day) == "day-one-without-steel"
  end

  test "a folder published is a blog of its published pages, with a feed", %{
    scope: scope,
    journal: journal,
    day: day
  } do
    {:ok, journal} = Publishing.publish(scope, journal)
    assert {:blog, _, []} = Publishing.resolve(["the-forge", "journal"])

    {:ok, day} = Publishing.publish(scope, day)
    assert Publishing.path(day) == "/the-forge/journal/day-one-without-steel"

    assert {:blog, _, [%{title: "Day one without steel"}]} =
             Publishing.resolve(["the-forge", "journal"])

    assert {:redirect, "/the-forge/journal/day-one-without-steel"} =
             Publishing.resolve(["the-forge", "day-one-without-steel"])

    assert {:feed, folder, posts} = Publishing.resolve(["the-forge", "journal", "feed.xml"])
    feed = Publishing.feed(folder, posts)
    assert feed =~ "<title>Day one without steel</title>"
    assert feed =~ "/the-forge/journal/day-one-without-steel</link>"
    assert Publishing.feed_url(journal) =~ "/the-forge/journal/feed.xml"
  end

  test "a person's handle is the index of their Private space's pages", %{
    scope: scope,
    hanzo: hanzo,
    kotoba: kotoba
  } do
    {:ok, note} =
      Pages.create(scope, %{"title" => "A note", "space_id" => Spaces.private!(hanzo).id})

    {:ok, note} = Publishing.publish(scope, note)
    {:ok, _} = Publishing.publish(scope, kotoba)
    assert Publishing.path(note) == "/hanzo/a-note"

    assert {:person, %{id: id}, %{pages: [%{title: "A note"}], blogs: []}} =
             Publishing.resolve(["hanzo"])

    assert id == hanzo.id
  end

  test "a space's slug is its index, and its admins change it", %{
    scope: scope,
    yuki: yuki,
    kotoba: kotoba
  } do
    {:ok, page} = Publishing.publish(scope, kotoba)
    forge = Spaces.get!(scope, page.space_id)
    assert forge.slug == "the-forge"
    assert {:space, _, %{pages: [%{title: "Kotoba"}]}} = Publishing.resolve(["the-forge"])

    assert {:error, _} = Spaces.set_slug(Scope.for_user(yuki), forge, "forge")
    assert {:error, "“hanzo” is someone's handle" <> _} = Spaces.set_slug(scope, forge, "hanzo")
    assert {:error, "A page is published as" <> _} = Spaces.set_slug(scope, forge, "kotoba")
    assert {:ok, forge} = Spaces.set_slug(scope, forge, "forge")

    assert Publishing.path(page) == "/forge/kotoba"
    assert {:redirect, "/forge/kotoba"} = Publishing.resolve(["the-forge", "kotoba"])

    # A Private space's pages are always under its person's handle.
    assert {:error, :fixed} = Spaces.set_slug(scope, Spaces.private!(scope.user), "mine")
    assert {:error, :fixed} = Spaces.set_publish_paths(scope, Spaces.private!(scope.user), "solo")
    assert forge.slug == "forge"
  end

  test "under a prefix, at another address, or the notebook's alone", %{
    scope: scope,
    kotoba: kotoba
  } do
    Application.put_env(:notebook, :publishing, url: "https://hattori.ai", prefix: "/libs")
    {:ok, page} = Publishing.publish(scope, kotoba)
    assert Publishing.url(page) == "https://hattori.ai/libs/the-forge/kotoba"
    assert {:page, _} = Publishing.resolve(["libs", "the-forge", "kotoba"])

    Application.put_env(:notebook, :publishing,
      url: "https://hattori.ai",
      prefix: "/libs",
      paths: :solo
    )

    assert Publishing.url(page) == "https://hattori.ai/libs/kotoba"
    assert {:page, _} = Publishing.resolve(["libs", "kotoba"])
    assert {:redirect, "/libs/kotoba"} = Publishing.resolve(["libs", "the-forge", "kotoba"])

    assert Publishing.origin?(URI.parse("https://hattori.ai"))
    refute Publishing.origin?(URI.parse("https://elsewhere.example"))
  end

  test "a published page's files are anyone's, at the notebook's address", %{
    scope: scope,
    kotoba: kotoba
  } do
    key = "2026/10/desk.jpg"

    doc = %{
      "root" => %{
        "children" => [
          %{"type" => "attachment", "key" => key, "url" => "/uploads/kotoba/" <> key}
        ]
      }
    }

    {:ok, kotoba} = Pages.publish(scope, kotoba, %Kotoba.Content{doc: doc, text: "", html: ""})

    refute Publishing.public_upload?(key)
    {:ok, kotoba} = Publishing.publish(scope, kotoba)
    assert Publishing.public_upload?(key)

    %{doc: %{"root" => %{"children" => [%{"url" => url}]}}} =
      Publishing.absolute_files(kotoba.body)

    assert url == NotebookWeb.Endpoint.url() <> "/uploads/kotoba/" <> key
  end

  describe "where pages are read: the notebook's settings and each space's choice" do
    test "the admins keep the site, its prefix and its name", %{scope: scope, kotoba: kotoba} do
      admin = Scope.for_user(user_fixture(%{name: "Okazaki Masamune", admin: true}))

      assert {:error, :forbidden} = Publishing.save_settings(scope, %{"url" => "https://x.dev"})

      assert {:error, %Ecto.Changeset{}} =
               Publishing.save_settings(admin, %{"url" => "hattori.ai/libs", "name" => "Hattori"})

      assert {:ok, %{url: "https://hattori.ai", prefix: "", name: "Hattori"}} =
               Publishing.save_settings(admin, %{
                 "url" => "https://hattori.ai/",
                 "name" => "Hattori"
               })

      {:ok, page} = Publishing.publish(scope, kotoba)
      assert Publishing.url(page) == "https://hattori.ai/the-forge/kotoba"

      # Saved empty, the address is the notebook's own.
      {:ok, _} = Publishing.save_settings(admin, %{"url" => "", "name" => "Notebook"})
      assert Publishing.url(page) == NotebookWeb.Endpoint.url() <> "/the-forge/kotoba"
    end

    test "a space's pages at the top, another's under a handle, both read", %{
      hanzo: hanzo,
      scope: scope,
      kotoba: kotoba
    } do
      {:ok, oss} = Spaces.create_team(scope, %{name: "OSS"})
      {:ok, oss} = Spaces.set_publish_paths(scope, oss, "solo")
      {:ok, jumon} = Pages.create(scope, %{"title" => "Jumon", "space_id" => oss.id})

      {:ok, jumon} = Publishing.publish(scope, jumon)
      {:ok, kotoba} = Publishing.publish(scope, kotoba)

      assert Publishing.path(jumon) == "/jumon"
      assert Publishing.path(kotoba) == "/the-forge/kotoba"
      assert {:page, %{id: id}} = Publishing.resolve(["jumon"])
      assert id == jumon.id
      assert {:page, _} = Publishing.resolve(["the-forge", "kotoba"])
      assert {:redirect, "/jumon"} = Publishing.resolve(["the-forge", "jumon"])

      # A space's index has its pages; a person's, those of their Private space.
      assert {:space, _, %{pages: [%{title: "Kotoba"}]}} = Publishing.resolve(["the-forge"])
      assert {:person, _, %{pages: []}} = Publishing.resolve([hanzo.handle])
    end

    test "only its admins choose", %{yuki: yuki, scope: scope} do
      {:ok, oss} = Spaces.create_team(scope, %{name: "OSS"})
      {:ok, _} = Spaces.add_member(scope, oss, yuki, "editor")
      assert {:error, _} = Spaces.set_publish_paths(Scope.for_user(yuki), oss, "solo")
    end

    test "slugs and handles are one list of names", %{
      hanzo: hanzo,
      yuki: yuki,
      scope: scope,
      kotoba: kotoba
    } do
      assert {:error, "“" <> _} = Publishing.publish(scope, kotoba, yuki.handle)

      {:ok, _} = Publishing.publish(scope, kotoba, "kotoba")

      assert {:error, changeset} =
               Notebook.Accounts.update_user_handle(hanzo, %{handle: "kotoba"})

      assert "is a page's address" in errors_on(changeset).handle

      # A new person's handle steps around a slug.
      assert Publishing.free_handle("Ana Kotoba") == "kotoba-2"
    end
  end
end
