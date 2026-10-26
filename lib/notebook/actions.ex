defmodule Notebook.Actions do
  @moduledoc """
  What people and agents do in the Notebook by the same way
  (`Issho.Action`): a person from the page (its command palette, its
  buttons and dialogs, a database's table and board), an agent as a tool.
  Each runs in a room, under its policy (`Notebook.Collaboration`: who
  reads and edits the page or the space, and not on what is off limits
  to agents), as whoever runs it, and the room hears it done
  (`"action.done"`). A paused agent changes nothing.

  A page's own (its room, `"page:<id>"`):

    * `RenamePage`, `SetDueDate`, `MovePage`, `ArchivePage`,
      `RestorePage`;
    * a database page's: `AddRecords`, `UpdateRecords`, `DeleteRecords`,
      `MoveRecord`, `AddField`, `AddView`.

  A space's (`"space:<id>"`): `CreatePage`.

  A person's only (`people/0`): who has a page or a folder (`Share`,
  `ShareLink`), whether agents may work on a page (`SetAgents`), and
  publishing (`Publish`, `Unpublish`). They are actions as the others
  are, run from the dialogs, and refuse an agent: what agents may reach
  is their people's to say.
  """

  alias Notebook.Pages

  @doc "Every action an agent may run: its tools."
  def all do
    [
      __MODULE__.CreatePage,
      __MODULE__.RenamePage,
      __MODULE__.SetDueDate,
      __MODULE__.MovePage,
      __MODULE__.ArchivePage,
      __MODULE__.RestorePage,
      __MODULE__.AddRecords,
      __MODULE__.UpdateRecords,
      __MODULE__.DeleteRecords,
      __MODULE__.MoveRecord,
      __MODULE__.AddField,
      __MODULE__.AddView
    ]
  end

  @doc "The actions only a person runs."
  def people,
    do: [
      __MODULE__.Share,
      __MODULE__.ShareLink,
      __MODULE__.SetAgents,
      __MODULE__.Publish,
      __MODULE__.Unpublish
    ]

  @doc "The room of the page of that id: the action's target."
  def room(page_id), do: "page:#{page_id}"

  @doc "The room of a page or a folder (its space's), by kind and id."
  def room("page", id), do: room(id)

  def room("folder", id) do
    case Notebook.Repo.get(Notebook.Spaces.Folder, id) do
      %{space_id: space_id} -> "space:#{space_id}"
      nil -> "space:none"
    end
  end

  @doc """
  The page and the scope of whoever runs the invocation (`by`), for its
  change. The room's policy has said they edit it.
  """
  def page(page_id, %Issho.Action.Invocation{} = invocation) do
    with {:ok, scope} <- scope(invocation),
         %Pages.Page{} = page <- Pages.fetch(page_id) do
      {:ok, scope, Notebook.Repo.preload(page, [:space, :folder])}
    else
      _ -> {:error, "No such page."}
    end
  end

  @doc "The page of that id and its database's collection, as `page/2`."
  def database(page_id, invocation) do
    with {:ok, scope, page} <- page(page_id, invocation) do
      case Notebook.Databases.collection(page) do
        %Cardbox.Collection{} = collection -> {:ok, scope, page, collection}
        nil -> {:error, "That page is not a database."}
      end
    end
  end

  @doc "The scope of whoever runs the invocation."
  def scope(%Issho.Action.Invocation{by: by}) do
    case Notebook.Collaboration.scope_of(by) do
      {:ok, scope} -> {:ok, scope}
      _error -> {:error, "Only a person, or their agent, does this."}
    end
  end

  @doc "A page or a folder, by kind and id."
  def resource("page", id), do: Pages.fetch(id)
  def resource("folder", id), do: Notebook.Repo.get(Notebook.Spaces.Folder, id)

  @doc "Refuses an agent, a bot or a visitor: for an action only a person runs."
  def person_only(%Issho.Identity{kind: :human}), do: :ok

  def person_only(_who),
    do: {:error, "Only a person does this: ask the person you work for."}

  @doc "What went wrong in a change, in words a person or a model reads."
  def error(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join(". ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
  end

  def error(%Cardbox.Error{reason: :unauthorized}), do: "You may not change this database."
  def error(%Cardbox.Error{message: message}), do: message
  def error(message) when is_binary(message), do: message
  def error(%Sekisho.Denied{}), do: "You may not do this here."
  def error(%{__exception__: true} = exception), do: Exception.message(exception)
  def error(_other), do: "You may not change this page."
end
