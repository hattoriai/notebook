defmodule Notebook.Accounts.Scope do
  @moduledoc """
  Defines the scope of the caller to be used throughout the app.

  The `Notebook.Accounts.Scope` allows public interfaces to receive
  information about the caller, such as if the call is initiated from an
  end-user, and if so, which user. Additionally, such a scope can carry fields
  such as "super user" or other privileges for use in authorization checks,
  or to ensure specific code paths can only be accessed for a given scope.

  It is useful for logging as well as for scoping pubsub subscriptions and
  broadcasts when a caller subscribes to an interface or performs a particular
  action.

  Feel free to extend the fields on this struct to fit the needs of
  growing application requirements.
  """

  alias Notebook.Accounts.User

  defstruct user: nil, link_tokens: []

  @doc """
  Creates a scope for the given user.

  Returns nil if no user is given.
  """
  def for_user(%User{} = user) do
    %__MODULE__{user: user}
  end

  def for_user(nil), do: nil

  @doc """
  The scope with the tokens of the links its person followed (pages and
  folders shared with anyone who has the link): what they may open.
  """
  def with_links(%__MODULE__{} = scope, tokens) when is_list(tokens),
    do: %{scope | link_tokens: tokens}

  def with_links(nil, _tokens), do: nil
end
