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
    key = Storehouse.key(file, description.content_type)
    meta = %{name: name, content_type: description.content_type, bytes: description.bytes}
    {:ok, url} = Storehouse.adapter().put(key, path, meta)

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

  # Dates near today, so that the index calendar shows them: due in a week,
  # about this week, a review on the next weekday at 14:00 in Lisbon, and a
  # revisit every two weeks from the due day.
  today = Date.utc_today()
  monday = Date.beginning_of_week(today)

  review_day =
    Stream.iterate(Date.add(today, 1), &Date.add(&1, 1))
    |> Enum.find(&(Date.day_of_week(&1) in 1..5))

  review_at =
    review_day
    |> DateTime.new!(~T[14:00:00], Pages.time_zone())
    |> DateTime.shift_zone!("Etc/UTC")

  {:ok, _} =
    Pages.create(Scope.for_user(hanzo), %{
      "title" => tour_title,
      "body" => body,
      "due_on" => Date.add(today, 7),
      "covers" => Date.range(monday, Date.add(monday, 4)),
      "review_at" => review_at,
      "revisit" => "FREQ=WEEKLY;INTERVAL=2"
    })
end

# Hanzo is not alone. Masamune, an old friend from the forges of Sagami,
# still makes blades; Yuki, Hanzo's last apprentice, now keeps a tea house.
# Sign in as either of them too, to see the notebook from their side.
person = fn name, email, password ->
  Accounts.get_user_by_email(email) ||
    (
      {:ok, user} = Accounts.register_user(%{name: name, email: email, password: password})
      user
    )
end

masamune = person.("Okazaki Masamune", "masamune@notebook.test", "the sharpest pen")
yuki = person.("Yuki Hattori", "yuki@notebook.test", "my first page")

alias Notebook.Spaces
alias Notebook.Spaces.{Folder, Space}

hanzo_scope = Scope.for_user(hanzo)
yuki_scope = Scope.for_user(yuki)

# A team space, made once by its first admin, with its people and roles.
team = fn scope, name, description, members ->
  space =
    Notebook.Repo.get_by(Space, kind: "team", name: name) ||
      elem(Spaces.create_team(scope, %{name: name, description: description}), 1)

  for {user, role} <- members, user.id != scope.user.id do
    Spaces.add_member(scope, space, user, role)
  end

  space
end

folder = fn scope, space, name, parent ->
  Notebook.Repo.get_by(Folder, space_id: space.id, name: name) ||
    elem(Spaces.create_folder(scope, space, %{name: name}, parent), 1)
end

# A text page from Markdown, made once (by its title).
text = fn scope, title, space, folder, markdown, attrs ->
  Notebook.Repo.get_by(Page, title: title) ||
    elem(
      Pages.create(
        scope,
        Map.merge(
          %{
            "title" => title,
            "space_id" => space.id,
            "folder_id" => folder && folder.id,
            "body" => Kotoba.Content.from_markdown(markdown)
          },
          attrs
        )
      ),
      1
    )
end

# The forge: Hanzo's old workshop, as a team. Masamune edits; Yuki may
# read and comment, as an apprentice does.
forge =
  team.(hanzo_scope, "The forge", "Where the last blades are planned and made.", [
    {masamune, "editor"},
    {yuki, "commenter"}
  ])

plans = folder.(hanzo_scope, forge, "Plans", nil)
in_progress = folder.(hanzo_scope, forge, "In progress", nil)
ceremonies = folder.(hanzo_scope, forge, "Ceremonies", plans)

# A board and a table, for agents and people to work on together.
unless Notebook.Repo.get_by(Page, title: "The forge, planned") do
  {:ok, _board} =
    Pages.create(hanzo_scope, %{
      "title" => "The forge, planned",
      "kind" => "board",
      "space_id" => forge.id,
      "folder_id" => plans.id
    })
end

unless Notebook.Repo.get_by(Page, title: "Blades in progress") do
  {:ok, table} =
    Pages.create(hanzo_scope, %{
      "title" => "Blades in progress",
      "kind" => "table",
      "space_id" => forge.id,
      "folder_id" => in_progress.id
    })

  for {title, status, owner, days, points} <- [
        {"Fold the steel", "done", "Hanzo", -3, 5},
        {"Quench the blade", "doing", "Hanzo", 2, 3},
        {"Polish the edge", "todo", "Masamune", 6, 8},
        {"Wrap the handle", "todo", nil, 9, 2}
      ] do
    Notebook.Repo.insert!(%Notebook.Pages.Row{
      page_id: table.id,
      title: title,
      status: status,
      owner: owner,
      due_on: Date.add(Date.utc_today(), days),
      points: points
    })
  end
end

# A page of charts of the table, live: they move as its rows change, and
# an agent changes them with change_chart.
numbers_title = "The forge in numbers"

unless Notebook.Repo.get_by(Page, title: numbers_title) do
  blades = Notebook.Repo.get_by!(Page, title: "Blades in progress")

  {:ok, numbers} =
    Pages.create(hanzo_scope, %{
      "title" => numbers_title,
      "space_id" => forge.id,
      "folder_id" => in_progress.id
    })

  {:ok, by_status} = Notebook.Charts.create(hanzo_scope, numbers, blades, "points_by_status")
  {:ok, by_week} = Notebook.Charts.create(hanzo_scope, numbers, blades, "due_by_week")

  embed = fn chart ->
    ref = JSON.encode!(%{kind: "chart", ref: to_string(chart.id), title: chart.spec["title"]})
    "<!-- kotoba:embed #{ref} -->\n\n#{chart.spec["title"]}\n\n<!-- /kotoba:embed -->"
  end

  body =
    Kotoba.Content.from_markdown("""
    The last blades, counted. Each chart reads *Blades in progress*: change a row there, and the bars move here.

    ## How far we have come

    #{embed.(by_status)}

    ## What falls due, and when

    #{embed.(by_week)}

    > Count the folds, not the days. — Hattori Hanzo
    """)

  {:ok, _} = Pages.update(hanzo_scope, numbers, %{"body" => body})
end

text.(
  hanzo_scope,
  "The last blade",
  forge,
  plans,
  """
  One more sword, and then no more. Not for a warrior: for the museum in Kyoto, so that people who never held steel can see what thirteen folds look like.

  ## What it needs

  - Tamahagane from the last smelt, the good half
  - Masamune's eye for the curve
  - Yuki at the bellows, one more time

  > A blade is finished when there is nothing left to take away.
  """,
  %{"due_on" => Date.add(Date.utc_today(), 21)}
)

text.(
  hanzo_scope,
  "The naming of the blade",
  forge,
  ceremonies,
  """
  The blade is named on the morning it leaves. Everyone who worked on it writes one word on a card; the words go in the box; the youngest draws one.

  1. Clean the forge, all of it
  2. Tea, the strong one
  3. The words, the box, the draw
  4. The name, cut into the tang
  """,
  %{}
)

text.(
  Scope.for_user(masamune),
  "Notes on the curve",
  forge,
  in_progress,
  """
  Hanzo likes a deep **sori**. I like it shallow. We will meet in the middle, as we have for forty years, and he will say it was his idea.

  | Part | Hanzo | Me |
  | --- | --- | --- |
  | Curve | deep | shallow |
  | Hamon | wild | straight |
  | Tea | strong | stronger |
  """,
  %{}
)

# A page that has done its work: archived, out of the sidebar, never lost.
old_orders =
  text.(
    hanzo_scope,
    "Sword orders, 1998",
    forge,
    nil,
    """
    Twelve orders this year. The last one from a man who wanted a sword to hang over his television. I said no. That was when I began to think about pages.
    """,
    %{}
  )

unless old_orders.archived_at, do: Pages.archive(hanzo_scope, old_orders)

# The tea house: Yuki's own space now. Hanzo edits; he insists on the menu.
tea_house =
  team.(
    yuki_scope,
    "Tea house",
    "Yuki's tea house by the river: the menu, the guests, the garden.",
    [
      {hanzo, "editor"}
    ]
  )

menu = folder.(yuki_scope, tea_house, "Menu", nil)

text.(
  yuki_scope,
  "Autumn menu",
  tea_house,
  menu,
  """
  ## Teas

  - **Hōjicha**, roasted, for the evenings
  - **Genmaicha**, for guests who are hungry and too polite to say so
  - **Gyokuro**, only when Master Hanzo is not looking at the price

  ## Sweets

  - Chestnut yōkan
  - Persimmon, dried by the window since September
  """,
  %{}
)

text.(
  yuki_scope,
  "The garden, by the season",
  tea_house,
  nil,
  """
  The maple by the gate turns first. Then the one by the water. Guests ask which is older; neither of us knows.
  """,
  %{"revisit" => "FREQ=MONTHLY"}
)

# Hanzo's Private space: his alone, and his agent's.
hanzo_private = Spaces.private!(hanzo)
journal = folder.(hanzo_scope, hanzo_private, "Journal", nil)

text.(
  hanzo_scope,
  "Day one without steel",
  hanzo_private,
  journal,
  """
  Woke at four, as always. Lit nothing. Sat with the cold forge and a cup of tea until the sun came through the shutters.

  *Wrote a page instead.* It was not very good. Neither was my first sword.
  """,
  %{}
)

text.(
  hanzo_scope,
  "Letters I never sent",
  hanzo_private,
  nil,
  """
  To Masamune: you were right about the curve. You will never read this.
  """,
  %{}
)

# Databases (Cardbox): records with fields, seen as a table, a board, a
# calendar and a chart. The forge keeps its commissions; Hanzo keeps what
# he reads.
alias Notebook.Cardbox, as: Box

database = fn scope, title, space, folder, fields, records ->
  page =
    Notebook.Repo.get_by(Page, title: title) ||
      elem(
        Pages.create(scope, %{
          "title" => title,
          "kind" => "database",
          "space_id" => space.id,
          "folder_id" => folder && folder.id,
          "fields" => fields
        }),
        1
      )

  collection = Notebook.Databases.collection(page)

  if Box.count(collection) == {:ok, 0} do
    for values <- records, do: {:ok, _} = Box.insert(collection, values, actor: scope)
  end

  {page, collection}
end

masamune_id = "user:#{masamune.id}"
hanzo_id = "user:#{hanzo.id}"
today = Date.utc_today()

{_commissions, commissions} =
  database.(
    hanzo_scope,
    "Commissions",
    forge,
    nil,
    [
      %{name: "Blade", type: "text"},
      %{name: "Client", type: "text"},
      %{
        name: "Status",
        type: "status",
        options: %{
          choices: [
            %{name: "Asked", group: "todo", color: "gray"},
            %{name: "Forging", group: "doing", color: "orange"},
            %{name: "Polishing", group: "doing", color: "yellow"},
            %{name: "Delivered", group: "done", color: "green"}
          ]
        }
      },
      %{name: "Smith", type: "person"},
      %{name: "Due", type: "date"},
      %{name: "Price", type: "number", options: %{format: "currency", currency: "JPY"}},
      %{
        name: "Kind",
        type: "select",
        options: %{
          choices: [
            %{name: "Katana", color: "red"},
            %{name: "Tantō", color: "blue"},
            %{name: "Wakizashi", color: "purple"},
            %{name: "Restoration", color: "brown"}
          ]
        }
      }
    ],
    [
      %{
        "Blade" => "The museum's last blade",
        "Client" => "Kyoto National Museum",
        "Status" => "Forging",
        "Smith" => hanzo_id,
        "Due" => Date.add(today, 21),
        "Price" => 0,
        "Kind" => "Katana"
      },
      %{
        "Blade" => "A tantō for a wedding",
        "Client" => "The Ōta family",
        "Status" => "Polishing",
        "Smith" => masamune_id,
        "Due" => Date.add(today, 5),
        "Price" => 380_000,
        "Kind" => "Tantō"
      },
      %{
        "Blade" => "Grandfather's wakizashi",
        "Client" => "Mr. Sato",
        "Status" => "Asked",
        "Smith" => masamune_id,
        "Due" => Date.add(today, 40),
        "Price" => 220_000,
        "Kind" => "Restoration"
      },
      %{
        "Blade" => "A pair for the dojo",
        "Client" => "Kōbukan dojo",
        "Status" => "Asked",
        "Smith" => hanzo_id,
        "Due" => Date.add(today, 60),
        "Price" => 900_000,
        "Kind" => "Wakizashi"
      },
      %{
        "Blade" => "The rain blade",
        "Client" => "A collector in Osaka",
        "Status" => "Delivered",
        "Smith" => masamune_id,
        "Due" => Date.add(today, -12),
        "Price" => 1_200_000,
        "Kind" => "Katana"
      },
      %{
        "Blade" => "A letter opener, at last",
        "Client" => "Yuki's tea house",
        "Status" => "Delivered",
        "Smith" => hanzo_id,
        "Due" => Date.add(today, -3),
        "Price" => 0,
        "Kind" => "Tantō"
      }
    ]
  )

# The chart counts by status; the commissions' worth is their price.
unless Enum.any?(Box.list_views(commissions), &(&1.name == "Worth by status")) do
  {:ok, _} =
    Box.save_view(
      commissions,
      %{
        name: "Worth by status",
        type: "chart",
        options: %{kind: "bar", x: "Status", y: %{sum: "Price"}, color: "Kind"}
      },
      actor: hanzo_scope
    )
end

database.(
  hanzo_scope,
  "Reading list",
  Spaces.private!(hanzo),
  nil,
  [
    %{name: "Title", type: "text"},
    %{name: "Author", type: "text"},
    %{
      name: "Status",
      type: "status",
      options: %{
        choices: [
          %{name: "To read", group: "todo"},
          %{name: "Reading", group: "doing"},
          %{name: "Read", group: "done"}
        ]
      }
    },
    %{name: "Rating", type: "number", options: %{format: "integer"}},
    %{name: "Finished", type: "date"}
  ],
  [
    %{
      "Title" => "Bushido, the Soul of Japan",
      "Author" => "Inazō Nitobe",
      "Status" => "Read",
      "Rating" => 4,
      "Finished" => Date.add(today, -30)
    },
    %{"Title" => "The Book of Five Rings", "Author" => "Miyamoto Musashi", "Status" => "Reading"},
    %{
      "Title" => "In Praise of Shadows",
      "Author" => "Jun'ichirō Tanizaki",
      "Status" => "To read"
    },
    %{
      "Title" => "The Unfettered Mind",
      "Author" => "Takuan Sōhō",
      "Status" => "Read",
      "Rating" => 5,
      "Finished" => Date.add(today, -9)
    }
  ]
)

# Hanzo's Inbox (Chime). Yuki added him to the Tea house above; here the
# others write to him, in comments (Issho), and Masamune hands him a
# commission. Made once, with the threads it tells of.
alias Notebook.Collaboration

as = fn user -> %{id: user.id, name: user.name} end
last_blade = Notebook.Repo.get_by!(Page, title: "The last blade")
autumn_menu = Notebook.Repo.get_by!(Page, title: "Autumn menu")
blade_room = Collaboration.room(last_blade)

if Issho.Comments.threads(Notebook.Issho, blade_room) == {:ok, []} do
  {:ok, %{thread: quench}} =
    Issho.Comments.start(
      Notebook.Issho,
      blade_room,
      as.(masamune),
      nil,
      "@Hattori Hanzo, the hamon on the museum blade wants one more quench. Shall I wait for you?",
      mentions: [to_string(hanzo.id)]
    )

  {:ok, _} =
    Issho.Comments.reply(
      Notebook.Issho,
      blade_room,
      as.(hanzo),
      quench,
      "Wait for me. Thursday, at dawn."
    )

  {:ok, _} =
    Issho.Comments.reply(
      Notebook.Issho,
      blade_room,
      as.(yuki),
      quench,
      "May I watch? I'll bring tea for after."
    )

  menu_room = Collaboration.room(autumn_menu)

  {:ok, %{thread: rice}} =
    Issho.Comments.start(
      Notebook.Issho,
      menu_room,
      as.(hanzo),
      nil,
      "The chestnut rice: less salt this year?"
    )

  {:ok, _} =
    Issho.Comments.reply(
      Notebook.Issho,
      menu_room,
      as.(yuki),
      rice,
      "Less salt, more chestnut. Come and taste it on Sunday."
    )

  # Masamune hands the wakizashi to his old master.
  {:ok, [wakizashi]} =
    Box.list(commissions, %{
      "filter" => %{"field" => "Blade", "op" => "eq", "value" => "Grandfather's wakizashi"}
    })

  {:ok, _} =
    Box.update(commissions, wakizashi, %{"Smith" => hanzo_id}, actor: Scope.for_user(masamune))

  # A letter of his is due today: its reminder comes at 09:00, or now.
  text.(
    hanzo_scope,
    "A reply to the museum",
    hanzo_private,
    journal,
    """
    They ask for the blade's story, for the card beside it. Keep it short:
    thirteen folds, one winter, and the last sword of the forge.
    """,
    %{"due_on" => Date.utc_today()}
  )
end

# Sharing (Sekisho's grants): Yuki shares her autumn menu with Masamune,
# who is not of the Tea house, to comment on; Hanzo shares his reading
# list with Yuki; and the forge's plan has a link anyone signed in may
# follow, to read. A link's token shows once: the seeds print it.
alias Notebook.Sharing

share = fn scope, title, user, role ->
  page = Notebook.Repo.get_by!(Page, title: title)
  {:ok, %{people: people}} = Sharing.access(scope, page)

  unless Enum.any?(people, &(&1.user.id == user.id)),
    do: {:ok, _} = Sharing.share(scope, page, user, role)
end

share.(yuki_scope, "Autumn menu", masamune, "commenter")
share.(hanzo_scope, "Reading list", yuki, "viewer")

forge_plan = Notebook.Repo.get_by!(Page, title: "The forge, planned")
{:ok, plan_token} = Sharing.link(hanzo_scope, forge_plan, "viewer")

# Publishing: Hanzo publishes the tour and the forge's numbers (their
# charts move for readers as the table changes), and his journal is a
# blog of the days he chose to publish.
alias Notebook.Publishing

publish = fn scope, resource, slug ->
  if Publishing.published?(resource),
    do: resource,
    else: elem(Publishing.publish(scope, resource, slug), 1)
end

tour_page =
  publish.(hanzo_scope, Notebook.Repo.get_by!(Page, title: "A tour of Notebook"), "tour")

numbers =
  publish.(
    hanzo_scope,
    Notebook.Repo.get_by!(Page, title: "The forge in numbers"),
    "forge-in-numbers"
  )

journal_blog = publish.(hanzo_scope, Notebook.Repo.get!(Folder, journal.id), "journal")

publish.(
  hanzo_scope,
  Notebook.Repo.get_by!(Page, title: "Day one without steel"),
  "day-one-without-steel"
)

# What notifies of all this is done before the script ends; Hanzo has
# read Yuki's invitation to the Tea house already.
Notebook.Notifications.settle()

for n <- Chime.feed("user:#{hanzo.id}", filter: :all),
    n.kind == "added_to_space",
    do: Chime.mark_read("user:#{hanzo.id}", [n.id])

IO.puts("""
Sign in as one of them:
  Hattori Hanzo      #{hanzo_email}   no more swords
  Okazaki Masamune   masamune@notebook.test   the sharpest pen
  Yuki Hattori       yuki@notebook.test   my first page

Anyone signed in may read The forge, planned with its link:
  #{Sharing.url(forge_plan, plan_token)}

Anyone may read what Hanzo published:
  #{Publishing.url(tour_page)}
  #{Publishing.url(numbers)}
  #{Publishing.url(journal_blog)}  (and its feed, #{Publishing.feed_url(journal_blog)})
  #{Publishing.person_url(hanzo_scope.user |> then(&Notebook.Repo.get!(Notebook.Accounts.User, &1.id)))}
""")
