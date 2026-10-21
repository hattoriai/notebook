# Notebook

A shared notebook where people and agents work together, live: a Phoenix app built on [Issho](https://github.com/hattoriai/issho), collaboration for Phoenix, and the libraries on it. A page is a text (Kotoba), a board of cards and arrows (Hakushi) or a table of tasks (Masu), and each page is an Issho room: everyone on it is listed once, their pointers move over the whole page, and their changes land as they make them. Connect Claude Code or Codex, and your agent works on the pages beside you: its cursor in the text, its pointer on the board, its cell in the table. Pages are stored in SQLite, each page's dates are picked with Koyomi, and Jumon's command palette (⌘K) finds pages and runs the notebook's actions.

## Run locally

This branch runs on the unreleased Issho, Kotoba, Hakushi and Masu: check them out next to this one, and build their assets once.

```sh
git clone https://github.com/hattoriai/issho ../issho
git clone -b claude/zen-ramanujan-g5n646 https://github.com/hattoriai/kotoba ../kotoba
git clone https://github.com/hattoriai/hakushi ../hakushi
git clone -b claude/zen-ramanujan-g5n646 https://github.com/hattoriai/masu ../masu
(cd ../issho && mix deps.get && mix issho.build)
(cd ../kotoba && mix deps.get && mix kotoba.build)
(cd ../hakushi && mix deps.get && mix hakushi.build)
(cd ../masu && mix deps.get && mix masu.build)
```

Then, with Elixir 1.18 or later (`.tool-versions` pins the versions used here):

```sh
mix setup
mix phx.server
```

Open <http://localhost:4000>, create an account with a name, email, and password, and start a page. Signup logs you in immediately; no email service is needed. To see live collaboration, register a second account in another browser profile and open the same page in both.

`mix setup` creates `tmp/notebook_dev.db`, runs the migrations and adds the sample pages. Attachments go to `tmp/uploads`. Set `NOTEBOOK_DATABASE` to use a different SQLite file. Both paths are ignored by Git.

## Connect an agent

Open **Agents** (`/agents`): it has the command that connects your agent to the Notebook, with your token in it. For Claude Code:

```sh
claude mcp add --transport http notebook "http://localhost:4000/mcp?token=…"
```

For Codex, `codex mcp add notebook --url "…"`, or the same URL in `~/.codex/config.toml`. Your agent works on your behalf, in the rooms of the pages: open a page in your browser, then ask it.

- “Open the board *The forge, planned*, add a card for each step of the ceremony, and join them in order.”
- “In *Blades in progress*, give every task without an owner to Masamune.”
- Select some words in a page, then: “Rewrite what I have selected in *A tour of Notebook*, plainer.”

It has every tool of the pages (`Notebook.Tools`): the Notebook's own (`list_pages`, `create_page`), Issho's for rooms, and those of Kotoba, Hakushi and Masu, which act on what a person has selected too. With no agent at hand, `scripts/agent.exs` is an MCP client that works on the sample pages:

```sh
mix run --no-start scripts/agent.exs "http://localhost:4000/mcp?token=…" board "The forge, planned"
```

## What to try

The sample pages (`mix setup`, or `mix run priv/repo/seeds.exs`) are **A tour of Notebook**, a text with every kind of block, photos from Unsplash, a gallery and a PDF; **The forge, planned**, a board; and **Blades in progress**, a table. Their author is Hattori Hanzo, a retired swordsmith who now makes pages: sign in as `hanzo@notebook.test` with the password `no more swords` to write as him.

- Open a page in two browsers, as two people: each is in the page's list of people once, and their pointers move over the whole page, on the same part of the other's page whatever its size; a click rings. Over **Only for you** parts nothing is shared.
- Make a **New page** of each kind. On a board, drag a **Card**, a **Note** or a **Frame** onto the paper, or double-click it; join cards from their sides, and the arrows say *then*; a page card opens its page. Cards snap to the paper's grid, and the controls zoom, fit, tidy up, undo and download the board. On a table, edit a cell as in a spreadsheet, paste rows from one, add and delete rows: the others see each change in the color of who made it, and a cell someone types in is theirs until they are done.
- **Maximize** a board or a table to the window (Esc restores it), or **Full screen**.
- Connect an agent (above) and watch it: in the list of people with *AI*, its status beside its name, its cursor, pointer or cell where it works, its changes as it makes them. Undo takes back your own last change on the page, whichever part you made it in.

- Select words to open the selection menu. The new-page editor uses Kotoba's default menu (`selection_menu`); the edit page brings its own Heroicons menu through `<.kotoba_selection_menu>`, with the Callout extension's command in it. Both get Notebook's ink style from `--kotoba-floating-*` properties in `app.css`.
- Put the caret in a link to open, edit, or remove it from the link card. Alt+F10 moves the focus to the menu or the card.
- Format headings, lists, checklists, quotes, links, code blocks, tables, text colors, and highlights.
- Type `@` to mention a registered person and `#` to mention a page.
- Upload images, PDFs, or MP4/WebM videos. PDFs and videos render inline; images can be grouped into galleries.
- Use the **Callout** toolbar control or type `!!! ` at the start of a paragraph. The callout is a custom Kotoba extension with an Elixir rendering node.
- Open one text as two users. The editor shows their cursors and selections, and the accepted save status. **Publish page** commits the current accepted revision to the reader view.
- Give a page its dates under the title, with Koyomi. **Due** is a date picker with presets; type a segment or a word into it ("next friday", "in 2 weeks"). **Covers** is a range of days, kept in SQLite as an ISO 8601 interval (`Koyomi.DateRange`, `storage: :string`). **Review together** picks a time in Lisbon from the free hours the LiveView offers (`Pages.review_slots/2`): weekdays from 10:00 to 16:00, with the hours another page's review takes disabled. **Revisit** is a repeat rule (`Koyomi.Recurrence`), and the reader says it in words with the next date. The changeset checks the same rules as the pickers (`Page.review_rules/0`).
- The calendar beside the page list marks each page's due day, covered days, review and revisits, and Portugal's public holidays. Pick a day to see the pages that have something on it.
- Copy a published page to the clipboard as Markdown or plain text, and search the cached text from the page list.
- Press ⌘K (Ctrl+K), or **Search or jump to…**, to open Jumon's command palette. It searches the pages by their title and their words (a source of the server; the titles are ranked with `Jumon.Match`, so a typo such as "notebok" still finds a page), and lists the pages changed last when the box is empty; → on a page offers **Edit together**. The actions of the whole notebook are in `NotebookWeb.Commands`: **New page** (`c`), **All pages** (`g h`), **Settings** (`g s`) and **Log out**. Press `?` for every shortcut.
- The palette also has the actions of what you look at, from `Jumon.Live.put_actions/2` in `NotebookLive`. On the page list, **Show a day** (`g d`) is a page of the next seven days, and picks the day in the calendar too. On a page, **Edit together** (`e`), **Rename this page…** (a text, checked on the server against the page's 160 characters), **Set the due date…** (a choice of days), **Copy link** and **Copy Markdown**.
- What each person runs is kept in SQLite (`Jumon.History.Ecto`, the `jumon_history` table), so **Recent** follows you to any browser.

Notebook is a single shared space. Any signed-in account can see and edit every page. The sample app does not have private workspaces or per-page permissions.

## Checks

```sh
mix test
mix precommit
```

## Try an unreleased change

Issho, Kotoba, Hakushi and Masu come from checkouts next to this one on this branch (see Run locally); after a change to one, run its build (`mix kotoba.build`...) and `mix assets.build` again. To test a change to Koyomi or Jumon before its release, put its checkout next to Notebook and point Notebook at it for a while. For Koyomi:

1. In `mix.exs`, use `{:koyomi, path: "../koyomi"}`.
2. In `assets/css/app.css`, import `../../../koyomi/priv/static/koyomi.css`.
3. Run `mix koyomi.build` in the checkout, then remove `deps/koyomi` (esbuild finds the Hex copy there first), run `mix deps.get` and `mix assets.build`, and restart the server.

Run `mix koyomi.build` and `mix assets.build` again after each change. Put the Hex versions back before you commit.
