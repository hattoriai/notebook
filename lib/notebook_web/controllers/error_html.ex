defmodule NotebookWeb.ErrorHTML do
  @moduledoc """
  The notebook's error pages, for HTML requests (config/config.exs): a
  page not found (404), and one that broke (500), in the notebook's paper
  and ink. Whole pages of their own, as an error may come before any
  layout: their styles from the notebook's own address, so that they read
  the same through a site's proxy (a published page's 404 at hattori.ai).

  The 500 asks nothing of the database: it may be what broke.
  """
  use NotebookWeb, :html

  def render("404.html", _assigns) do
    {name, home} = site()

    error_page(%{
      code: "404",
      title: "This page isn't in the notebook.",
      line:
        "It may have been unpublished, moved or archived, or it was never written. The address may have a typo, too.",
      drawing: :blank,
      home: home,
      home_label: "Go to #{name}"
    })
  end

  def render("500.html", _assigns) do
    error_page(%{
      code: "500",
      title: "The ink spilled.",
      line: "Something broke on our side, not yours. Your pages are safe. Try again in a moment.",
      drawing: :spill,
      home: "/",
      home_label: "Back to the notebook"
    })
  end

  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)

  # The site readers came from (its published pages' site, else the
  # notebook), and nothing more if the database does not answer.
  defp site do
    %{name: name, url: url} = Notebook.Publishing.config()
    {name, url <> "/"}
  rescue
    _error -> {"Notebook", "/"}
  end

  attr :code, :string, required: true
  attr :title, :string, required: true
  attr :line, :string, required: true
  attr :drawing, :atom, values: [:blank, :spill], required: true
  attr :home, :string, required: true
  attr :home_label, :string, required: true

  defp error_page(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en" data-theme="light">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="robots" content="noindex" />
        <meta name="theme-color" content="#f6f3ec" />
        <title>{@code} · {@title}</title>
        <link
          rel="icon"
          href={static_url(NotebookWeb.Endpoint, ~p"/images/favicon.svg")}
          type="image/svg+xml"
        />
        <link rel="stylesheet" href={static_url(NotebookWeb.Endpoint, ~p"/assets/css/app.css")} />
      </head>
      <body class="error-body">
        <main class="error-page" id={"error-#{@code}"}>
          <div class="error-drawing" aria-hidden="true">
            <.drawing kind={@drawing} />
          </div>
          <p class="error-code">{@code}</p>
          <h1>{@title}</h1>
          <p class="error-line">{@line}</p>
          <p class="error-actions">
            <a class="button button-primary" href={@home}>{@home_label}</a>
            <a :if={@code == "500"} class="copy-action" href="">Try again</a>
          </p>
        </main>
        <a class="error-mark" href="https://hattori.ai">Notebook, by Hattori AI</a>
      </body>
    </html>
    """
  end

  attr :kind, :atom, required: true

  # A notebook's page, drawn in ink: blank, its corner folded (a page not
  # there); or with the ink spilled across it (a page that broke).
  defp drawing(%{kind: :blank} = assigns) do
    ~H"""
    <svg viewBox="0 0 160 190" fill="none" stroke-linecap="round" stroke-linejoin="round">
      <path
        d="M30 18h74l30 30v122a6 6 0 0 1-6 6H30a6 6 0 0 1-6-6V24a6 6 0 0 1 6-6Z"
        class="error-paper"
      />
      <path d="M104 18v24a6 6 0 0 0 6 6h24" class="error-ink" stroke-width="2.2" />
      <path
        d="M30 18h74l30 30v122a6 6 0 0 1-6 6H30a6 6 0 0 1-6-6V24a6 6 0 0 1 6-6Z"
        class="error-ink"
        stroke-width="2.2"
      />
      <path
        d="M44 74h70M44 92h70M44 110h50"
        class="error-rule"
        stroke-width="2"
        stroke-dasharray="2 7"
      />
      <path d="M44 140c10-8 18 8 28 0s18 8 28 0" class="error-accent" stroke-width="2.2" />
    </svg>
    """
  end

  defp drawing(%{kind: :spill} = assigns) do
    ~H"""
    <svg viewBox="0 0 190 190" fill="none" stroke-linecap="round" stroke-linejoin="round">
      <path
        d="M30 18h74l30 30v122a6 6 0 0 1-6 6H30a6 6 0 0 1-6-6V24a6 6 0 0 1 6-6Z"
        class="error-paper"
      />
      <path
        d="M30 18h74l30 30v122a6 6 0 0 1-6 6H30a6 6 0 0 1-6-6V24a6 6 0 0 1 6-6Z"
        class="error-ink"
        stroke-width="2.2"
      />
      <path d="M104 18v24a6 6 0 0 0 6 6h24" class="error-ink" stroke-width="2.2" />
      <path d="M44 74h70M44 92h40" class="error-rule" stroke-width="2" stroke-dasharray="2 7" />
      <path
        d="M78 118c-14-4-30 4-28 18 2 12 16 12 20 22 3 8 14 10 22 4 8-6 20-2 26-10 7-9-2-20-10-22-6-2-6-10-14-12-6-2-10 2-16 0Z"
        class="error-blot"
      />
      <circle cx="132" cy="150" r="5" class="error-blot" />
      <circle cx="146" cy="166" r="3" class="error-blot" />
      <path d="m150 40 22-22 8 8-22 22-12 4 4-12Z" class="error-ink" stroke-width="2.2" />
      <path d="m166 24 8 8" class="error-ink" stroke-width="2.2" />
    </svg>
    """
  end
end
