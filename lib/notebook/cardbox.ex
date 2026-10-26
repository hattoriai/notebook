defmodule Notebook.Cardbox do
  @moduledoc """
  The collections of database pages (Cardbox). A collection belongs to its
  page (`owner: {"page", id}`): who may change its records, fields and
  views is who may edit the page (`Notebook.Permissions`), and who may
  read it is who may read the page, as the pages context scopes it.
  """
  use Cardbox, repo: Notebook.Repo, pubsub: Notebook.PubSub

  alias Notebook.Accounts.{Scope, User}
  alias Notebook.Pages

  @impl Cardbox
  def actor_id(%Scope{user: %User{id: id}}), do: "user:#{id}"
  def actor_id(%User{id: id}), do: "user:#{id}"
  def actor_id(_actor), do: nil

  @impl Cardbox
  def allow?(%Scope{} = scope, _action, %Cardbox.Collection{owner_type: "page", owner_id: id}),
    do: editable?(scope, id)

  def allow?(%Scope{} = scope, :create_collection, %{"owner_type" => "page", "owner_id" => id}),
    do: editable?(scope, id)

  def allow?(_actor, _action, _subject), do: false

  # A bill paid that repeats comes back on its rule's next day, with the
  # update (Notebook.Cardbox.Repeat).
  @impl Cardbox
  def after_update(collection, before, record, changed),
    do: {:ok, Notebook.Cardbox.Repeat.next(collection, before, record, changed)}

  defp editable?(scope, id) do
    case Pages.fetch(to_id(id)) do
      nil -> false
      page -> Pages.allowed?(scope, :edit, page)
    end
  end

  defp to_id(id) when is_integer(id), do: id
  defp to_id(id), do: String.to_integer(to_string(id))
end
