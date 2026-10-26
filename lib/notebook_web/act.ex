defmodule NotebookWeb.Act do
  @moduledoc """
  A person's action from a LiveView (`Notebook.Actions`): run in the
  action's room as the person, the LiveView joining it first when it is
  not in it yet (a new page's space, a folder's): the same action, under
  the same policy, as their agent's tool.
  """

  @doc "Runs the action as the scope's person, in its room. Options: `Issho.Live.act/3`'s."
  def act(scope, action, args, opts \\ []) do
    with {:ok, room} <- Issho.Action.room(action, args),
         {:ok, _session} <- Issho.Live.join(Notebook.Issho, person(scope), room) do
      Issho.Live.act(action, args, opts)
    end
  end

  @doc """
  The person of a scope as the rooms know them: their account, and the
  links they followed (`Notebook.Sharing`), signed into their identity.
  """
  def person(%{user: account, link_tokens: links}) do
    person = %{
      id: to_string(account.id),
      name: account.name,
      color: Notebook.Accounts.User.color(account)
    }

    if links == [], do: person, else: Issho.Identity.new(person, claims: %{links: links})
  end
end
