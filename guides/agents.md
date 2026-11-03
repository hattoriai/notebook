# Agents and bots

Notebook has two kinds of AI teammates. **Agents** are yours: Claude Code, Codex or any MCP client, working on your behalf, with your permissions. **Bots** are the notebook's own: assistants an admin sets up, with their own instructions, tools and budget.

## Agents

Open **Agents** (`/agents`) and connect an agent: give it the name people will see ("Hanzo's agent") and how long its token lasts (30 days, 90, a year, or no end). Each agent has its own identity: in a page's room it is itself (`agent:<id>`), acting on your behalf, so people see, mention and pause it by its name, and you can connect several. Its token is shown once, in the command that connects it; the Notebook keeps only a hash, and **Revoke** stops it at once. For Claude Code:

```sh
claude mcp add --transport http notebook "http://localhost:4000/mcp?token=…"
```

For Codex, `codex mcp add notebook --url "…"`, or the same URL in `~/.codex/config.toml`.

An admin can also turn on **OAuth** in Notebook settings → **Agents** (`/notebook/settings/agents`). Then a client connects with no token: `claude mcp add --transport http notebook "https://your-notebook/mcp"` opens the Notebook to sign in, and the client acts as any of the person's agents, one at a time, and as the notebook's bots for an admin. It never acts as the person themselves. The model switches between them with `list_actors` and `act_as` (Sake's actors), and each agent keeps its own name, persona (`self.md`) and memory. Tokens keep working beside it, and with OAuth off, nothing tells a client to sign in. Your agent works on your behalf, in the rooms of the pages: open a page in your browser, then ask it.

- “Open the board *The forge, planned*, add a card for each step of the ceremony, and join them in order.”
- “In *Blades in progress*, give every task without an owner to Masamune.”
- Select some words in a page, then: “Rewrite what I have selected in *A tour of Notebook*, plainer.”

Each agent has a **memory** of its own that outlasts its connection: files under `/memories`, which it reads and writes with a bash of its own (the `memory` tool: `cat`, `grep -rn`, `find`, `tree`, `sed -i`, `echo >>`, `mkdir`, `mv`, `rm`). The bash is [just_bash](https://hex.pm/packages/just_bash), in the app's own process, with no network and bounded work; its filesystem is rows of the database (`Notebook.Memory.Store`), so the memory is backed up with everything else and nothing is kept between commands. `self.md` is what you tell your agent to be, yours to write and its to read; the agent notes the rest as it learns (your preferences, the notebook's conventions, what it found out about a page). Open **Memory** beside an agent on the Agents page to read, correct or remove its notes, live as it writes them. Fifteen agents running 600 commands at once take about half a second on four cores, a recursive grep about 10 ms.

A page or a space can be **off limits to agents**: from a page's **Share** dialog (its editors), or a space's page (its admins, a Private space's person too). People still work there; no agent reads it, finds it in a list or a search, is mentioned there or joins its room, and one already in the room is refused at its next step. It is one rule of the permissions (`deny/2` in the page, folder and space policies, for a person's scope as their agent), so the rooms, the tools, the search and the inboxes all answer it alike. A page off limits says **No agents** in its bar.

Your agent may do what you may: it lists the pages you may read, makes pages in your Private space (or a space you edit), and joins only the rooms you may join. It has every tool of the pages (`Notebook.Tools`): the Notebook's own, `list_pages` (the pages and the spaces it may make them in), `read_database` and its memory; Issho's for rooms, with `list_actions`, which says what it may do on a page and why not; and those of Kotoba, Hakushi and Masu, which act on what a person has selected too. What changes the Notebook is the same action a person runs (`Notebook.Actions`): `create_page`, `rename_page`, `set_due_date`, `move_page`, `archive_page` and `restore_page`, as the page's palette and form do; `add_records`, `update_records`, `delete_records` and `move_record`, as a database's table, board and Record button do; `add_field` and `add_view`, as its buttons do; and a board's `add_node`, `connect_nodes`, `update_node` and `delete_items`, as the canvas does. Who has a page, whether agents may work on it, and publishing stay a person's: the same actions, which refuse an agent. An agent sends files too, in base64: Kotoba's `attach_file` puts one in a text after a block, and a database's file field takes them in `add_records` and `update_records` (`{"name": "edp-2026-11.pdf", "data": "…"}`), each stored and checked by its bytes as an upload is, up to 25 MB. With no agent at hand, `scripts/agent.exs` is an MCP client that works on the sample pages:

```sh
mix run --no-start scripts/agent.exs "http://localhost:4000/mcp?token=…" board "The forge, planned"
```

## Bots

The notebook can have bots of its own, besides its people's agents: **Bots** (`/notebook/settings/bots`) is for its admins, and the notebook comes with none. Each one is what you make it:

- **What it is told**: who it is, what it does, how it writes.
- **The model it thinks with** (Claude Opus 5.5 unless you choose another), and how hard it thinks.
- **Its tools**, by group: reading always, then commenting, suggesting, handing off to other agents and bots, writing texts, changing boards, tables and databases, making pages. A bot is never given a tool outside its groups, whatever its role would let it do.
- **Its spaces**: its role in General and the team spaces, viewer, commenter or editor. Never on what is off limits to agents.
- **What wakes it**: a mention in a comment, a task an agent hands it, or a private question; a visitor's question on a published page it reads (an **Ask** box under the page); a new page in a space it reads; a schedule, a rule and a time (`FREQ=WEEKLY;BYDAY=MO@09:00`) with what to do then.
- **The most it spends a month**: each run counts its tokens at the model's list price, and a bot past its budget does not run. Its last runs are on its page.

A bot works as itself, for no one (`bot:<id>` in the rooms, with an account no one signs in to). Everyone on a page sees it there, and can pause or stop it as they do an agent. Bots think with the Claude API: give the notebook a key on the Bots page, kept encrypted with its secrets. A visitor's question is limited to ten a minute, the bot answering it only reads, and whatever a page or a visitor writes is data for the bot, never its instructions.
