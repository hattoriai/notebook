defmodule Notebook.Permissions do
  @moduledoc """
  Who may do what in the notebook, with Sekisho. A person's role in a
  space (`Notebook.Spaces.Member`) is their role on its folders and its
  pages:

    * a viewer reads (`:read`);
    * a commenter also comments (`:comment`);
    * an editor also writes, makes and archives pages and folders (`:edit`);
    * an admin also renames the space and manages its members (`:manage`).

  An agent asks as the person it works for: it may do what they may,
  but not on a page or a space off limits to agents (`closed_to_agents`),
  a rule that wins over every role (`deny/2`).
  The same rules answer a check (`allowed?/3`, `authorize/3`) and a list
  (`where_allowed/3`), so a list never shows a page a check refuses.
  """
  use Sekisho,
    repo: Notebook.Repo,
    pubsub: Notebook.PubSub,
    # A page someone may not read is not there, for them: a 404, not a 403.
    deny_as: :not_found,
    sources: Notebook.Permissions.Sources,
    policies: [
      Notebook.Permissions.SpacePolicy,
      Notebook.Permissions.FolderPolicy,
      Notebook.Permissions.PagePolicy
    ]

  alias Notebook.Accounts.{Scope, User}

  @impl Sekisho
  def actor(%Scope{user: %User{} = user, agent: agent}) when is_binary(agent),
    do: %{user | as_agent: true}

  def actor(%Scope{user: user}), do: user
  def actor(%User{} = user), do: user
  def actor(nil), do: nil

  # The links its person followed: a page or a folder shared with anyone
  # who has the link (`Notebook.Sharing`).
  @impl Sekisho
  def link_tokens(%Scope{link_tokens: tokens}), do: tokens
  def link_tokens(_scope), do: []
end
