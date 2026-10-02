# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Notebook.Repo.insert!(%Notebook.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

# The SQL of each query is noise here.
Logger.configure(level: :info)

# Hattori Hanzo, retired swordsmith, now writes pages. He is the author of
# the tour. Sign in as him with the email and password below.
alias Notebook.Accounts
alias Notebook.Accounts.Scope

hanzo_email = "hanzo@notebook.test"

hanzo =
  Accounts.get_user_by_email(hanzo_email) ||
    elem(
      Accounts.register_user(%{
        name: "Hattori Hanzo",
        email: hanzo_email,
        password: "no more swords"
      }),
      1
    )

# A tour page that shows the reader view with every kind of block, with
# photos from Unsplash (see priv/repo/seed_images/CREDITS.md), a gallery and
# a PDF. It is added once: run the seeds again and it stays as it is.
alias Notebook.Pages
alias Notebook.Pages.Page

tour_title = "A tour of Notebook"

unless Notebook.Repo.get_by(Page, title: tour_title) do
  images = Path.expand("seed_images", __DIR__)

  # Stores a file as an upload does, and returns its attachment node. The
  # name is what readers see: the caption, and the alt text of an image.
  attachment = fn file, name ->
    path = Path.join(images, file)
    {:ok, description} = Kotoba.Attachments.describe(path, MIME.from_path(path))
    key = Kotoba.Storage.key(file, description.content_type)
    meta = %{name: name, content_type: description.content_type, bytes: description.bytes}
    {:ok, url} = Kotoba.Storage.adapter().put(key, path, meta)

    description
    |> Kotoba.Attachments.node(key: key, url: url, name: name)
    |> Kotoba.Node.to_json()
  end

  blocks = fn markdown -> Kotoba.Content.from_markdown(markdown).doc["root"]["children"] end

  gallery = fn nodes ->
    %{
      "type" => "gallery",
      "version" => 1,
      "direction" => nil,
      "format" => "",
      "indent" => 0,
      "children" => nodes
    }
  end

  children =
    blocks.("""
    I am **Hattori Hanzo**. For twenty-eight years I made steel. Then I swore an oath: no more swords. Now I make *pages*. This page shows what a Notebook page can hold, as a reader sees it after *Publish page*.
    """) ++
      [attachment.("desk.jpg", "The new workshop: laptop, open notebook and a cup of tea")] ++
      blocks.("""
      ## Made with Kotoba

      Every blade has a smith. This notebook has **Kotoba**: 言葉, Japanese for *words*. Kotoba is rich text for Phoenix. It gives a LiveView form an editor built on [Lexical](https://lexical.dev), stores each page with an Ecto type that keeps its HTML and plain text, and renders safe HTML, text and Markdown. Notebook is its demo: every page you read here, and every editor you write in, is Kotoba.

      A page needs one field:

      ```elixir
      schema "pages" do
        field :title, :string
        field :body, Kotoba.Content
      end
      ```

      and its form needs one component: `<.kotoba field={@form[:body]} selection_menu />`. Kotoba is [on Hex](https://hex.pm/packages/kotoba); the rest is in the [Kotoba repository](https://github.com/hattoriai/kotoba) and its [guides](https://hexdocs.pm/kotoba). I made swords that cut. Kotoba makes words that stay.

      ## Writing

      A good edit is a clean cut. Select any words in the editor and a small menu opens over them: **bold**, *italic*, underline, ~~strikethrough~~, `inline code`, a highlight, or a [link to the Elixir site](https://elixir-lang.org). Put the caret in a link to open it, change it or remove it.

      > If on your journey you should meet a typo, the typo will be cut.
      > — Hattori Hanzo

      ## Images and files

      My workshop is quieter now. Drop, paste or attach images, and group them in a gallery: select an image and use *Gallery* in the toolbar, or move it with Alt and the arrow keys.
      """) ++
      [
        gallery.([
          attachment.("fountain-pen.jpg", "The only blade I still sharpen"),
          attachment.("notes.jpg", "A notebook page titled Notes"),
          attachment.("writing.jpg", "Folding words, not steel")
        ])
      ] ++
      blocks.("""
      Every swordsmith keeps one book. Mine is Nitobe's *Bushido, the Soul of Japan*, from 1905. Here is its chapter on the sword, in the browser's own PDF viewer, with a link to download it.
      """) ++
      [
        attachment.(
          "the-sword-the-soul-of-the-samurai.pdf",
          "The Sword, the Soul of the Samurai (Nitobe, 1905).pdf"
        )
      ] ++
      blocks.("""
      ### Rules of the workshop

      - Headings, quotes and lists start with Markdown: `## `, `> `, `- `
      - Mentions start with `@` for people and `#` for pages
      - Files go in with a drop, a paste or the paper clip

      1. Write a draft
      2. Invite a student to edit together
      3. Publish the page

      - [x] Make one more page
      - [ ] Make one more sword

      ## Code

      ```elixir
      defmodule Hattori.Steel do
        @moduledoc "Fold, temper, polish. Then ship."

        def fold(layers, times \\\\ 13) when times > 0 do
          Enum.reduce(1..times, layers, fn _, acc -> acc * 2 end)
        end
      end
      ```

      ## Tables

      | Feature | Editor | Reader |
      | --- | --- | --- |
      | Selection menu | yes | — |
      | Live cursors | yes | — |
      | Syntax colors | yes | yes |
      | Galleries and PDFs | yes | yes |
      """) ++
      [attachment.("library.jpg", "Where old swords go to become stories")] ++
      blocks.("""
      Copy this page as Markdown or plain text with the buttons at the top. Or keep it, and come back to it later. Steel rusts. Pages wait.
      """)

  body = %{
    "kotoba" => 1,
    "lexical" => "0.51",
    "root" => %{
      "type" => "root",
      "version" => 1,
      "direction" => nil,
      "format" => "",
      "indent" => 0,
      "children" => children
    }
  }

  {:ok, _} = Pages.create(Scope.for_user(hanzo), %{"title" => tour_title, "body" => body})
end

IO.puts("Hattori Hanzo can sign in as #{hanzo_email} with the password \"no more swords\".")
