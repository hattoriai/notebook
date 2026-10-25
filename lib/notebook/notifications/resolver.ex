defmodule Notebook.Notifications.Resolver do
  @moduledoc "Who the notifications' people are (`Chime.Resolver`): the Notebook's accounts, as `user:<id>`."
  @behaviour Chime.Resolver

  import Ecto.Query

  alias Notebook.Accounts.User
  alias Notebook.Repo

  @impl true
  def recipient(%User{} = user) do
    %Chime.Recipient{
      id: Notebook.Notifications.id(user),
      email: user.email,
      name: user.name,
      time_zone: Notebook.Notifications.time_zone()
    }
  end

  @impl true
  def recipients(ids) do
    ids = for "user:" <> id <- ids, {id, ""} <- [Integer.parse(id)], do: id
    from(u in User, where: u.id in ^ids) |> Repo.all() |> Enum.map(&recipient/1)
  end

  @impl true
  def resolve_recipient(%{assigns: %{current_scope: %{user: %User{} = user}}}),
    do: recipient(user)

  def resolve_recipient(_nobody), do: nil
end
