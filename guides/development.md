# Development

## Run locally

Notebook uses the published Issho, Kotoba, Hakushi, Masu, Koyomi, Jumon, Sekisho, Narabe, Fude, Storehouse, Cardbox and Chime from Hex, as your app would. With Elixir 1.18 or later (`.tool-versions` pins the versions used here):

```sh
mix setup
mix phx.server
```

Open <http://localhost:4000>, create an account with a name, email, and password, and start a page. Signup logs you in immediately; no email service is needed: a new account is in General, with a Private space of its own. To see live collaboration, register a second account in another browser profile and open the same page in both, or sign in as two of the sample people (see the [tour](tour.md)).

`mix setup` creates `tmp/notebook_dev.db`, runs the migrations and adds the sample pages. Attachments go to `tmp/uploads` (Storehouse; `NOTEBOOK_UPLOADS` in production). Set `NOTEBOOK_DATABASE` to use a different SQLite file. Both paths are ignored by Git.

## Checks

```sh
mix test
mix precommit
```

## Try an unreleased change

To test a change to one of the libraries before its release, put its checkout next to Notebook and point Notebook at it for a while. For Koyomi:

1. In `mix.exs`, use `{:koyomi, path: "../koyomi"}`.
2. In `assets/css/app.css`, import `../../../koyomi/priv/static/koyomi.css`.
3. Run `mix koyomi.build` in the checkout, then remove `deps/koyomi` (esbuild finds the Hex copy there first), run `mix deps.get` and `mix assets.build`, and restart the server.

Run `mix koyomi.build` and `mix assets.build` again after each change. Issho, Kotoba, Hakushi and Masu work the same way, with their own build task (`mix kotoba.build`...). Put the Hex versions back before you commit.
