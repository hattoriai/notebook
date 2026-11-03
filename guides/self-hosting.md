# Self-hosting

Notebook is one Phoenix app with one SQLite database. A small server (2 vCPUs and 4 GB of memory is plenty for a team) runs it, and other apps beside it.

## Deploy with Kamal

The repository has what a deploy with [Kamal 2](https://kamal-deploy.org) needs: a `Dockerfile` (the release, with the SQLite database and the uploads on a volume at `/data`), `config/deploy.yml`, and `GET /up`, the health check kamal-proxy polls. kamal-proxy gets the TLS certificate from Let's Encrypt and routes by host, so the server may serve other apps too.

`config/deploy.yml` keeps nothing of one deploy's own. It reads:

| Variable | What it is |
|---|---|
| `NOTEBOOK_SERVER` | The server's IP or hostname. Kamal connects to it over SSH. |
| `NOTEBOOK_HOST` | The address people reach the notebook at, such as `notebook.example.com`. |
| `NOTEBOOK_IMAGE` | The image in your registry, such as `you/notebook`. |
| `NOTEBOOK_REGISTRY` | The registry. Default: `ghcr.io`. |
| `NOTEBOOK_SSH_USER` | The SSH user. Default: `root`. |

The first time:

1. Get a server (Ubuntu or Debian, amd64) that your SSH key opens. Kamal installs Docker.
2. Point the host's DNS (an A record, and an AAAA record for IPv6) to the server, before the next steps: Let's Encrypt must reach it.
3. Copy `.kamal/secrets.example` to `.kamal/secrets` and fill it in. Git ignores it. Keep `NOTEBOOK_VAULT_KEY` with your backups: the notebook's secrets cannot be read without it.
4. Set the variables, then set up the server:

   ```sh
   export NOTEBOOK_SERVER=203.0.113.10 NOTEBOOK_HOST=notebook.example.com NOTEBOOK_IMAGE=you/notebook
   kamal setup
   ```

   You can keep the variables in `.env` (git ignores it too) and load them with `set -a; . ./.env; set +a`.

After that, `kamal deploy` with the same variables. Each deploy builds the image on the server (`builder.remote`: the BEAM does not run under the emulation an arm64 Mac uses), runs the migrations (`bin/migrate`), and sends traffic to the new container when `/up` answers. `kamal app logs` shows the log, and `kamal app exec -i 'bin/notebook remote'` opens a console.

Back up the volume: the database is `/data/notebook.db` (`sqlite3 /data/notebook.db ".backup copy.db"` makes a consistent copy) and the files kept on the server's disk are in `/data/uploads`.

## Where files are kept

The notebook's first person is its admin. **Notebook settings** (the account menu, `/notebook/settings`) has a group at each address: **People** (who joins), **Agents** (how agents connect), **Bots** and **Files**. **Files** chooses where the pages' images and attachments are kept: on this server's disk, or in a bucket of any store that speaks S3 (Amazon S3, Cloudflare R2, Tigris, Backblaze B2, MinIO). A Google Drive, Dropbox or OneDrive works through [`rclone serve s3`](https://rclone.org/commands/rclone_serve_s3/). A bucket is tried before it is kept, and nothing needs deploying again.

Files keep their addresses (`/uploads/kotoba/…`) wherever they are, so pages never change. The notebook serves each file from the store that has it, behind the same rules as before: sent through the notebook (the bucket stays private) or by links the bucket signs for five minutes. After a move, **Copy them** copies the files of before to the new store, and **Remove them** then frees the room they took where they were, only for the files the new store has, the same size. Either runs in the background a slice at a time with a progress bar, the time left and a **Stop**: it may take hours, and it carries on after a restart.

The page also shows this server's disk: what the files, the database and everything else take, and what is free.

## Secrets

The notebook's secrets (a bucket's key, and the tokens and webhook secrets to come) are encrypted in the database (AES-256-GCM with Erlang's `:crypto`, `Notebook.Secrets`). The key is `NOTEBOOK_VAULT_KEY` (`openssl rand -base64 32`); without it, one is derived from `SECRET_KEY_BASE`, so a notebook needs nothing more to start. To rotate, set the new key, keep the old ones in `NOTEBOOK_VAULT_RETIRED_KEYS` (comma-separated), restart, and encrypt them again:

```sh
bin/notebook eval "Notebook.Secrets.rotate()"
```

Each secret names the key it was encrypted with, and the key derived from `SECRET_KEY_BASE` is always kept among the retired, so setting `NOTEBOOK_VAULT_KEY` for the first time needs no more. A secret no key opens any more is asked for again.

The SQLite database stays on the server's disk: on Fly.io, give it a volume.
