defmodule Notebook.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Notebook.Repo

  alias Notebook.Accounts.{User, UserIdentity, UserToken, UserNotifier}

  ## Database getters

  @doc "Every account, by name: the people of the notebook."
  # People, not bots' accounts (Notebook.Bots).
  def list_users, do: Repo.all(from u in User, where: not u.bot, order_by: u.name)

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Registers a user: a member of General, with a Private space of its own.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    changeset = User.registration_changeset(%User{}, attrs)
    name = Ecto.Changeset.get_field(changeset, :name)

    with {:ok, user} <-
           changeset
           |> Ecto.Changeset.put_change(:handle, Notebook.Publishing.free_handle(name))
           |> Ecto.Changeset.put_change(:admin, not Repo.exists?(User))
           |> Repo.insert() do
      Notebook.Spaces.welcome(user)
    end
  end

  def change_user_registration(user, attrs \\ %{}, opts \\ []) do
    User.registration_changeset(user, attrs, opts)
  end

  def change_user_handle(user, attrs \\ %{}),
    do: user |> User.handle_changeset(attrs) |> not_a_slug()

  @doc "Changes a person's handle: the paths of the pages they publish change with it."
  def update_user_handle(user, attrs), do: user |> change_user_handle(attrs) |> Repo.update()

  # Slugs and handles are one list of names (Notebook.Publishing): a page at
  # the top of the site and a person's index are at the same level.
  defp not_a_slug(changeset) do
    Ecto.Changeset.validate_change(changeset, :handle, fn :handle, handle ->
      if Notebook.Publishing.slug?(handle), do: [handle: "is a page's address"], else: []
    end)
  end

  def change_user_name(user, attrs \\ %{}) do
    user
    |> Ecto.Changeset.cast(attrs, [:name])
    |> Ecto.Changeset.validate_required([:name])
    |> Ecto.Changeset.validate_length(:name, min: 2, max: 60)
  end

  def update_user_name(user, attrs), do: user |> change_user_name(attrs) |> Repo.update()

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `Notebook.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `Notebook.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are three cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email and no password is set.
     In this case, the user gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The user has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/account/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## OpenID Connect

  @doc "The external identities linked to this user."
  def get_user_identities(%User{id: id}) do
    Repo.all(from i in UserIdentity, where: i.user_id == ^id, order_by: [desc: i.inserted_at])
  end

  @doc "Finds a user by external identity provider, issuer, and subject id."
  def get_user_by_identity(provider, issuer, uid) do
    from(i in UserIdentity,
      join: u in assoc(i, :user),
      where: i.provider == ^provider and i.issuer == ^issuer and i.uid == ^uid and not u.bot,
      select: u
    )
    |> Repo.one()
  end

  @doc """
  Resolves a user from verified OIDC claims:
    1. If already linked by provider, issuer, and sub, returns the user.
    2. If an existing human user has this email, links this identity and returns the user.
    3. If new and allowed (auto_register or valid invitation), provisions the user,
       sets admin if first person, links identity, and welcomes them to their spaces.
  """
  def resolve_oidc_user(claims, opts \\ []) do
    email = claims[:email] || claims["email"]

    email_verified =
      claims[:email_verified] == true or claims["email_verified"] in [true, "true", 1, "1"]

    sub = to_string(claims[:sub] || claims["sub"])
    issuer = to_string(claims[:issuer] || claims["issuer"])

    cond do
      not is_binary(email) or email == "" ->
        {:error, :missing_email}

      not email_verified ->
        {:error, :unverified_email}

      not Notebook.OIDC.domain_allowed?(email) ->
        {:error, :domain_not_allowed}

      user = get_user_by_identity("oidc", issuer, sub) ->
        from(i in UserIdentity,
          where: i.provider == "oidc" and i.issuer == ^issuer and i.uid == ^sub
        )
        |> Repo.update_all(set: [email: email, updated_at: DateTime.utc_now(:second)])

        {:ok, user}

      user = Repo.one(from u in User, where: u.email == ^String.downcase(email) and not u.bot) ->
        Repo.transact(fn ->
          Repo.insert!(%UserIdentity{
            user_id: user.id,
            provider: "oidc",
            issuer: issuer,
            uid: sub,
            email: email
          })

          user =
            if is_nil(user.confirmed_at) do
              Repo.update!(User.confirm_changeset(user))
            else
              user
            end

          {:ok, user}
        end)

      true ->
        provision_oidc_user(claims, issuer, sub, email, opts)
    end
  end

  defp provision_oidc_user(claims, issuer, sub, email, opts) do
    invite_token = opts[:invite]
    auto_register? = Notebook.OIDC.config().auto_register

    if auto_register? or Notebook.Invitations.open?(invite_token) do
      raw_name = claims[:name] || claims["name"] || hd(String.split(email, "@"))
      name = raw_name |> String.trim() |> String.slice(0, 60)
      name = if String.length(name) >= 2, do: name, else: "User"
      now = DateTime.utc_now(:second)

      Repo.transact(fn ->
        admin? = not Repo.exists?(from u in User, where: not u.bot)
        handle = Notebook.Publishing.free_handle(name)

        user =
          Repo.insert!(%User{
            name: name,
            email: String.downcase(email),
            handle: handle,
            admin: admin?,
            confirmed_at: now
          })

        Repo.insert!(%UserIdentity{
          user_id: user.id,
          provider: "oidc",
          issuer: issuer,
          uid: sub,
          email: email
        })

        if is_binary(invite_token) and invite_token != "" do
          Notebook.Invitations.consume(invite_token, user)
        end

        Notebook.Spaces.welcome(user)
      end)
    else
      {:error, :invite_only}
    end
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
