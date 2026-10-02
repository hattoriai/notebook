# Notebook

A shared notebook built to exercise Kotoba in a complete Phoenix app. Everyone with an account can write and read the same pages. Pages are stored in SQLite, files are served through authenticated routes, and collaborative edits are saved with Kotoba's revision authority.

## Run locally

Notebook currently uses the sibling Kotoba checkout so changes to Kotoba can be tested before release. Put both directories next to each other:

```text
hattori/
  kotoba/
  notebook/
```

Use Elixir 1.18 or later. The included `.tool-versions` pins the versions used here. Build Kotoba's package bundle once, then set up Notebook:

```sh
cd kotoba
mix deps.get
mix kotoba.build
cd ../notebook
mix setup
mix phx.server
```

Open <http://localhost:4000>, create an account with a name, email, and password, and start a page. Signup logs you in immediately; no email service is needed. To see live collaboration, register a second account in another browser profile and open the same page in both.

`mix setup` creates `tmp/notebook_dev.db` and runs the migrations. Attachments go to `tmp/uploads`. Set `NOTEBOOK_DATABASE` to use a different SQLite file. Both paths are ignored by Git.

## What to try

Run `mix run priv/repo/seeds.exs` to add **A tour of Notebook**, a page with every kind of block, photos from Unsplash, a gallery and a PDF. Its author is Hattori Hanzo, a retired swordsmith who now makes pages: sign in as `hanzo@notebook.test` with the password `no more swords` to write as him.

- Select words to open the selection menu. The new-page editor uses Kotoba's default menu (`selection_menu`); the edit page brings its own Heroicons menu through `<.kotoba_selection_menu>`, with the Callout extension's command in it. Both get Notebook's ink style from `--kotoba-floating-*` properties in `app.css`.
- Put the caret in a link to open, edit, or remove it from the link card. Alt+F10 moves the focus to the menu or the card.
- Format headings, lists, checklists, quotes, links, code blocks, tables, text colors, and highlights.
- Type `@` to mention a registered person and `#` to mention a page.
- Upload images, PDFs, or MP4/WebM videos. PDFs and videos render inline; images can be grouped into galleries.
- Use the **Callout** toolbar control or type `!!! ` at the start of a paragraph. The callout is a custom Kotoba extension with an Elixir rendering node.
- Open one page as two users. The editor shows participant names, cursors, selections, and accepted save status. **Publish page** commits the current accepted revision to the reader view.
- Copy a published page to the clipboard as Markdown or plain text, and search the cached text from the page list.

Notebook is a single shared space. Any signed-in account can see and edit every page. The sample app does not have private workspaces or per-page permissions.

## Checks

```sh
mix test
mix precommit
```

Run `mix kotoba.build` again in the sibling checkout whenever Kotoba's editor assets or stylesheet change, then run `mix assets.build` in Notebook.
