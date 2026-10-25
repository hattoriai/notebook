defmodule NotebookWeb.Router do
  use NotebookWeb, :router

  import NotebookWeb.UserAuth
  import Sake.Router
  import Chime.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {NotebookWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  # The links of the notifications' emails: one-click unsubscribe, which a
  # mail client posts with no session.
  pipeline :mail do
    plug :accepts, ["html"]
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # MCP clients, signed in by their person's token (the Agents page).
  pipeline :agent do
    plug NotebookWeb.AgentAuth
  end

  scope "/" do
    pipe_through :mail
    chime_mail("/notifications/mail", app_name: "Notebook")
  end

  scope "/" do
    pipe_through :agent
    sake_endpoint("/mcp", server: NotebookWeb.MCP, secret: {NotebookWeb.AgentAuth, :secret, []})
  end

  scope "/", NotebookWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :notebook_authenticated,
      on_mount: [
        {NotebookWeb.UserAuth, :require_authenticated},
        {Chime.Live, limit: 15},
        {Jumon.Live, NotebookWeb.Commands},
        Issho.Live,
        Masu.Live,
        NotebookWeb.Sidebar
      ] do
      live "/", NotebookLive, :index
      live "/pages/new", NotebookLive, :new
      live "/pages/:id", NotebookLive, :show
      live "/pages/:id/edit", NotebookLive, :edit
      live "/spaces/new", SpaceLive, :new
      live "/spaces/:id", SpaceLive, :show
      live "/spaces/:id/folders/:folder_id", SpaceLive, :folder
      live "/spaces/:id/members", SpaceLive, :members
      live "/archive", ArchiveLive, :index
      live "/inbox", InboxLive, :index
      live "/agents", AgentsLive, :index
    end

    # The files of the pages (Storehouse), for those signed in.
    get "/uploads/kotoba/*key", Storehouse.Local.Plug, [at: "/uploads/kotoba"], alias: false
  end

  # Other scopes may use custom stacks.
  # scope "/api", NotebookWeb do
  #   pipe_through :api
  # end

  ## Authentication routes

  scope "/", NotebookWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{NotebookWeb.UserAuth, :require_authenticated}, Chime.Live] do
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

  # The emails sent in development (the notifications'), to read them.
  if Application.compile_env(:notebook, :dev_routes) do
    scope "/dev" do
      pipe_through :browser
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
