defmodule Notebook.PageIconTest do
  # SQLite takes one writer at a time: these write files and rows, so they run alone.
  use Notebook.DataCase, async: false

  import Notebook.AccountsFixtures

  alias Notebook.Accounts.Scope
  alias Notebook.{Pages, Publishing, Spaces}
  alias Notebook.Pages.Page

  # A 1×1 PNG: an image by its bytes.
  @png Base.decode64!(
         "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
       )

  setup do
    hanzo = user_fixture(%{name: "Hattori Hanzo"})
    yuki = user_fixture(%{name: "Yuki Hattori"})
    grace = user_fixture(%{name: "Grace"})
    scope = Scope.for_user(hanzo)
    {:ok, forge} = Spaces.create_team(scope, %{name: "The forge"})
    {:ok, _} = Spaces.add_member(scope, forge, yuki, "editor")
    {:ok, _} = Spaces.add_member(scope, forge, grace, "viewer")
    {:ok, blade} = Pages.create(scope, %{"title" => "The last blade", "space_id" => forge.id})

    %{
      scope: scope,
      yuki: Scope.for_user(yuki),
      grace: Scope.for_user(grace),
      forge: forge,
      blade: blade
    }
  end

  defp png(name \\ "kotoba.png") do
    path = Path.join(System.tmp_dir!(), "page-icon-#{System.unique_integer([:positive])}-#{name}")
    File.write!(path, @png)
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp stored?("image:/uploads/kotoba/" <> key) do
    {:ok, path} = Storehouse.Local.path(key)
    File.exists?(path)
  end

  test "one of the notebook's icons, an emoji, or its kind's again; its editors may",
       %{yuki: yuki, blade: blade} do
    assert {:ok, %Page{icon: "hero-fire"}} = Pages.set_icon(yuki, blade, "hero-fire")
    assert {:ok, %Page{icon: "🔥"} = blade} = Pages.set_icon(yuki, blade, "🔥")
    assert {:ok, %Page{icon: nil}} = Pages.set_icon(yuki, blade, "")
  end

  test "nothing else, and not its readers", %{scope: scope, grace: grace, blade: blade} do
    assert {:error, %Ecto.Changeset{}} = Pages.set_icon(scope, blade, "hero-not-ours")
    assert {:error, %Ecto.Changeset{}} = Pages.set_icon(scope, blade, "a")
    assert {:error, %Ecto.Changeset{}} = Pages.set_icon(scope, blade, "image:javascript:x")
    assert {:error, _denied} = Pages.set_icon(grace, blade, "🔥")
    assert {:error, _denied} = Pages.set_icon_image(grace, blade, png(), "kotoba.png")
  end

  test "an image of its own, by its bytes; the one it had goes when it has another",
       %{scope: scope, blade: blade} do
    assert {:ok, %Page{icon: "image:/uploads/kotoba/" <> _ = first} = blade} =
             Pages.set_icon_image(scope, blade, png(), "kotoba.png")

    assert stored?(first)

    {:ok, %Page{icon: second} = blade} = Pages.set_icon_image(scope, blade, png(), "kotoba.png")
    refute stored?(first)
    assert stored?(second)

    {:ok, _blade} = Pages.set_icon(scope, blade, "🔥")
    refute stored?(second)

    text = Path.join(System.tmp_dir!(), "page-icon-#{System.unique_integer([:positive])}.png")
    File.write!(text, "not an image")
    on_exit(fn -> File.rm(text) end)
    assert {:error, {:image, _reason}} = Pages.set_icon_image(scope, blade, text, "fake.png")
  end

  test "anyone may read the image of a published page's icon, only while it is published",
       %{scope: scope, blade: blade} do
    {:ok, blade} = Pages.set_icon_image(scope, blade, png(), "kotoba.png")
    "image:/uploads/kotoba/" <> key = blade.icon

    refute Publishing.public_upload?(key)
    {:ok, blade} = Publishing.publish(scope, blade)
    assert Publishing.public_upload?(key)
    {:ok, blade} = Publishing.unpublish(scope, blade)
    refute Publishing.public_upload?(key)

    # Its image goes with it: no file is left for the other tests' stores.
    {:ok, _blade} = Pages.set_icon(scope, blade, "")
  end

  test "a published page's tab icon: its image, its emoji as an SVG, else the site's",
       %{blade: blade} do
    assert Publishing.favicon(%{blade | icon: "image:/uploads/kotoba/2026/11/a.png"}) =~
             ~r{^https?://.+/uploads/kotoba/2026/11/a\.png$}

    assert "data:image/svg+xml," <> svg = Publishing.favicon(%{blade | icon: "🔥"})
    assert URI.decode(svg) =~ "🔥"
    assert Publishing.favicon(%{blade | icon: "hero-fire"}) == nil
    assert Publishing.favicon(%{blade | icon: nil}) == nil
  end

  test "the images of a space's pages go with the space", %{
    scope: scope,
    forge: forge,
    blade: blade
  } do
    {:ok, blade} = Pages.set_icon_image(scope, blade, png(), "kotoba.png")
    {:ok, forge} = Spaces.archive(scope, forge)
    {:ok, _forge} = Spaces.delete(scope, forge)

    refute stored?(blade.icon)
  end
end
