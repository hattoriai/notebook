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

  test "its editors publish a page under a slug, at its publisher's path", %{
    scope: scope,
    yuki: yuki,
    kotoba: kotoba
  } do
    assert {:error, _} = Publishing.publish(Scope.for_user(yuki), kotoba)

    {:ok, page} = Publishing.publish(scope, kotoba)
    assert page.slug == "kotoba"
    assert Publishing.url(page) == NotebookWeb.Endpoint.url() <> "/hanzo/kotoba"
    assert {:page, %{id: id}} = Publishing.resolve(["hanzo", "kotoba"])
    assert id == kotoba.id

    {:ok, page} = Publishing.unpublish(scope, page)
    assert page.slug == "kotoba"
    assert Publishing.resolve(["hanzo", "kotoba"]) == :not_found
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
    assert {:blog, _, []} = Publishing.resolve(["hanzo", "journal"])

    {:ok, day} = Publishing.publish(scope, day)
    assert Publishing.path(day) == "/hanzo/journal/day-one-without-steel"

    assert {:blog, _, [%{title: "Day one without steel"}]} =
             Publishing.resolve(["hanzo", "journal"])

    assert {:redirect, "/hanzo/journal/day-one-without-steel"} =
             Publishing.resolve(["hanzo", "day-one-without-steel"])

    assert {:feed, folder, posts} = Publishing.resolve(["hanzo", "journal", "feed.xml"])
    feed = Publishing.feed(folder, posts)
    assert feed =~ "<title>Day one without steel</title>"
    assert feed =~ "/hanzo/journal/day-one-without-steel</link>"
    assert Publishing.feed_url(journal) =~ "/hanzo/journal/feed.xml"
  end

  test "a person's handle is their index", %{scope: scope, hanzo: hanzo, kotoba: kotoba} do
    {:ok, _} = Publishing.publish(scope, kotoba)

    assert {:person, %{id: id}, %{pages: [%{title: "Kotoba"}], blogs: []}} =
             Publishing.resolve(["hanzo"])

    assert id == hanzo.id
  end

  test "under a prefix, at another address, or the notebook's alone", %{
    scope: scope,
    kotoba: kotoba
  } do
    Application.put_env(:notebook, :publishing, url: "https://hattori.ai", prefix: "/libs")
    {:ok, page} = Publishing.publish(scope, kotoba)
    assert Publishing.url(page) == "https://hattori.ai/libs/hanzo/kotoba"
    assert {:page, _} = Publishing.resolve(["libs", "hanzo", "kotoba"])

    Application.put_env(:notebook, :publishing,
      url: "https://hattori.ai",
      prefix: "/libs",
      paths: :solo
    )

    assert Publishing.url(page) == "https://hattori.ai/libs/kotoba"
    assert {:page, _} = Publishing.resolve(["libs", "kotoba"])
    assert {:redirect, "/libs/kotoba"} = Publishing.resolve(["libs", "hanzo", "kotoba"])

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
end
