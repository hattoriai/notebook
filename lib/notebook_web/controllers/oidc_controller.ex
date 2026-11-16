defmodule NotebookWeb.OIDCController do
  use NotebookWeb, :controller

  alias Notebook.{Accounts, OIDC}
  alias NotebookWeb.UserAuth

  def request(conn, params) do
    config = OIDC.config()

    if config.enabled do
      redirect_uri = url(~p"/users/oidc/callback")

      case OIDC.authorize_url(config.issuer, config.client_id, redirect_uri) do
        {:ok, %{url: url, state: state, nonce: nonce, code_verifier: verifier}} ->
          conn
          |> put_session(:oidc_state, state)
          |> put_session(:oidc_nonce, nonce)
          |> put_session(:oidc_code_verifier, verifier)
          |> maybe_put_invite(params["invite"])
          |> redirect(external: url)

        {:error, reason} ->
          conn
          |> put_flash(:error, "Could not start sign-in: #{describe(reason)}")
          |> redirect(to: ~p"/users/log-in")
      end
    else
      conn
      |> put_flash(:error, "Single Sign-On is not enabled.")
      |> redirect(to: ~p"/users/log-in")
    end
  end

  def callback(conn, %{"error" => error} = params) do
    conn = clear_oidc_session(conn)
    desc = params["error_description"] || error

    conn
    |> put_flash(:error, "Sign-in was not completed: #{desc}")
    |> redirect(to: ~p"/users/log-in")
  end

  def callback(conn, %{"code" => code, "state" => state}) do
    session_state = get_session(conn, :oidc_state)
    nonce = get_session(conn, :oidc_nonce)
    code_verifier = get_session(conn, :oidc_code_verifier)
    invite = get_session(conn, :oidc_invite)
    conn = clear_oidc_session(conn)

    cond do
      not is_binary(session_state) or session_state == "" ->
        conn
        |> put_flash(:error, "Sign-in session expired. Please try again.")
        |> redirect(to: ~p"/users/log-in")

      not Plug.Crypto.secure_compare(session_state, state) ->
        conn
        |> put_flash(:error, "Invalid sign-in state. Please try again.")
        |> redirect(to: ~p"/users/log-in")

      true ->
        redirect_uri = url(~p"/users/oidc/callback")

        case OIDC.authenticate(code, code_verifier, nonce, redirect_uri) do
          {:ok, claims} ->
            case Accounts.resolve_oidc_user(claims, invite: invite) do
              {:ok, user} ->
                conn
                |> put_flash(:info, "Welcome, #{user.name}.")
                |> UserAuth.log_in_user(user, %{"remember_me" => "true"})

              {:error, :domain_not_allowed} ->
                conn
                |> put_flash(:error, "Your email domain is not permitted to join this notebook.")
                |> redirect(to: ~p"/users/log-in")

              {:error, :unverified_email} ->
                conn
                |> put_flash(
                  :error,
                  "Your email address must be verified by your identity provider."
                )
                |> redirect(to: ~p"/users/log-in")

              {:error, :invite_only} ->
                conn
                |> put_flash(
                  :error,
                  "This notebook is invite only. Ask one of its admins for an invitation."
                )
                |> redirect(to: ~p"/users/log-in")

              {:error, reason} ->
                conn
                |> put_flash(:error, "Could not complete sign-in: #{describe(reason)}")
                |> redirect(to: ~p"/users/log-in")
            end

          {:error, reason} ->
            conn
            |> put_flash(:error, "Authentication failed: #{describe(reason)}")
            |> redirect(to: ~p"/users/log-in")
        end
    end
  end

  def callback(conn, _params) do
    conn
    |> clear_oidc_session()
    |> put_flash(:error, "Invalid response from identity provider.")
    |> redirect(to: ~p"/users/log-in")
  end

  defp maybe_put_invite(conn, invite) when is_binary(invite) and invite != "" do
    put_session(conn, :oidc_invite, invite)
  end

  defp maybe_put_invite(conn, _), do: conn

  defp clear_oidc_session(conn) do
    conn
    |> delete_session(:oidc_state)
    |> delete_session(:oidc_nonce)
    |> delete_session(:oidc_code_verifier)
    |> delete_session(:oidc_invite)
  end

  defp describe(reason) when is_binary(reason), do: reason
  defp describe(reason), do: inspect(reason)
end
