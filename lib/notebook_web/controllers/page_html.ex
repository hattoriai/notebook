defmodule NotebookWeb.PageHTML do
  @moduledoc """
  The pages of `NotebookWeb.PageController`: the front page and Made with.
  See the `page_html` directory for their templates.
  """
  use NotebookWeb, :html

  embed_templates "page_html/*"

  # Hattori AI's libraries the notebook is made with, and what each does in
  # it. Their logos are in priv/static/images/libraries, as each library's
  # media/logo.svg (and hattori.ai's).
  @libraries [
    {"issho", "Issho", "Collaboration",
     "Each page is a room: who is on it, their pointers, and their changes as they make them."},
    {"kotoba", "Kotoba", "Rich text", "The text of a page, its images and its links."},
    {"hakushi", "Hakushi", "Canvas", "Boards of cards and arrows."},
    {"masu", "Masu", "Tables", "Tables of tasks, edited cell by cell."},
    {"cardbox", "Cardbox", "Collections", "Databases of records, with the fields you give them."},
    {"koyomi", "Koyomi", "Dates", "The dates of pages and tasks."},
    {"erabi", "Erabi", "Pickers",
     "Every choice in a list: roles, people, places, models, and when you hear of things."},
    {"jumon", "Jumon", "Commands", "The command palette (⌘K): pages, spaces and actions."},
    {"fude", "Fude", "Charts", "Charts of a page's numbers."},
    {"narabe", "Narabe", "Ordering",
     "The spaces, folders and pages of the sidebar, in the order you put them."},
    {"sekisho", "Sekisho", "Permissions",
     "Who may read, comment on or edit each page, and what agents may do."},
    {"chime", "Chime", "Notifications", "The Inbox, the bell, and the emails."},
    {"storehouse", "Storehouse", "Files",
     "Uploads, on the server or in any bucket that speaks S3."},
    {"sake", "Sake", "MCP", "The tools of Claude Code, Codex and other agents."}
  ]

  @doc "The libraries: their id (the logo's and the repository's name), name, kind and use."
  def libraries do
    for {id, name, kind, use} <- @libraries,
        do: %{id: id, name: name, kind: kind, use: use, url: "https://github.com/hattoriai/#{id}"}
  end
end
