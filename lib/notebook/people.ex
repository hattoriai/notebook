defmodule Notebook.People do
  import Ecto.Query
  alias Notebook.Accounts.User
  alias Notebook.Repo

  def search(query) do
    pattern = "%" <> String.trim(query) <> "%"

    from(u in User, where: like(u.name, ^pattern), order_by: u.name, limit: 20)
    |> Repo.all()
    |> Enum.map(fn user ->
      %{id: user.id, label: user.name, hint: "Person"}
    end)
  end
end
