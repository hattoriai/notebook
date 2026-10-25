defmodule Notebook.Notifier do
  @moduledoc """
  The Notebook's notifiers' common ground (`Chime.Notifier`): each goes to
  the person's Inbox at once, and by email ten minutes later unless they
  read it by then. A notification of a page goes only to someone who may
  read the page when it comes (`may_read?/2`), and its email is its feed's
  words, with a link that reads it.
  """
  defmacro __using__(opts) do
    quote do
      use Chime.Notifier, unquote(opts)

      deliver :feed, if: :may_read?
      deliver :email, wait: {10, :minute}, unless: :read, if: :may_read?

      @doc false
      def may_read?(%{"page_id" => id}, recipient),
        do: Notebook.Notifications.may_read?(Notebook.Notifications.user(recipient.id), id)

      def may_read?(_data, _recipient), do: true

      @impl Chime.Notifier
      def email(data, recipient, notification),
        do: Notebook.Notifier.email(feed(data, notification), recipient, notification)

      defoverridable email: 3
    end
  end

  @doc "An email of what a notification's feed says."
  def email(feed, recipient, notification) do
    link = Chime.link(notification, feed[:url] || "/")
    body = feed[:body]

    Swoosh.Email.new(
      to: {recipient.name, recipient.email},
      subject: feed.title,
      text_body: Enum.join(Enum.reject([feed.title, body, "Open it: " <> link], &is_nil/1), "\n\n"),
      html_body: """
      <p style="font:16px/1.5 Georgia,serif;color:#1c1917">#{escape(feed.title)}</p>
      #{if body, do: ~s(<blockquote style="margin:0 0 16px;padding-left:12px;border-left:3px solid #e4ddd0;color:#57534e">#{escape(body)}</blockquote>), else: ""}
      <p><a href="#{escape(link)}" style="color:#a3502e">Open it in Notebook</a></p>
      """
    )
  end

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  @doc "Who did it, as a notification keeps them: an account, or an Issho identity (a person or an agent)."
  def actor(nil), do: nil
  def actor(%Notebook.Accounts.User{} = user), do: %{"id" => Notebook.Notifications.id(user), "name" => user.name}

  def actor(%Issho.Identity{key: key, name: name}) do
    case Integer.parse(to_string(key)) do
      {id, ""} -> %{"id" => "user:#{id}", "name" => name}
      _agent -> %{"id" => "agent:#{key}", "name" => name}
    end
  end

  @doc "The first words of a text, for a line of the Inbox."
  def excerpt(nil), do: nil

  def excerpt(text) do
    text = text |> String.replace(~r/\s+/, " ") |> String.trim()
    if String.length(text) > 140, do: String.slice(text, 0, 139) <> "…", else: text
  end
end
