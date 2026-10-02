defmodule NotebookWeb.Router do
  use NotebookWeb, :router

  import NotebookWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {NotebookWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", NotebookWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :notebook_authenticated,
      on_mount: [{NotebookWeb.UserAuth, :require_authenticated}] do
      live "/", NotebookLive, :index
      live "/pages/new", NotebookLive, :new
      live "/pages/:id", NotebookLive, :show
      live "/pages/:id/edit", NotebookLive, :edit
    end

    get "/uploads/kotoba/*key", Kotoba.Storage.Local.Plug, [at: "/uploads/kotoba"], alias: false
  end

  # Other scopes may use custom stacks.
  # scope "/api", NotebookWeb do
  #   pipe_through :api
  # end

  ## Authentication routes

  scope "/", NotebookWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{NotebookWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", NotebookWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{NotebookWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
    end

    post "/users/log-in", UserSessionController, :create
    post "/users/register", RegistrationController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
