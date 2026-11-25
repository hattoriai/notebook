defmodule Notebook.People do
  @moduledoc "The people of the notebook (not bots) by name: those an \"@\" in a text offers."
  import Ecto.Query
  alias Notebook.Accounts.User
  alias Notebook.Repo

  def search(query) do
    pattern = "%" <> String.trim(query) <> "%"

    from(u in User, where: like(u.name, ^pattern) and not u.bot, order_by: u.name, limit: 20)
    |> Repo.all()
    |> Enum.map(fn user ->
      %{id: user.id, label: user.name, hint: "Person"}
    end)
  end
end
