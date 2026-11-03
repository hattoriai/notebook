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
    plug :keep_link_token
    plug :fetch_current_scope_for_user
  end

  # The links of the notifications' emails: one-click unsubscribe, which a
  # mail client posts with no session.
  pipeline :mail do
    plug :accepts, ["html"]
  end

  # The published pages (Notebook.Publishing): anyone reads them, at paths
  # of the notebook's own, under its publishing prefix; a blog's feed too.
  pipeline :public do
    plug :accepts, ["html", "xml"]
    plug :fetch_session
    plug NotebookWeb.Plugs.Guest
    plug NotebookWeb.Plugs.Feed
    plug :put_root_layout, html: {NotebookWeb.Layouts, :public_root}
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # The Notebook's OAuth server for MCP clients: there only when Notebook
  # settings turn it on.
  pipeline :mcp_oauth do
    plug NotebookWeb.Plugs.MCPOAuth
  end

  # The health check kamal-proxy polls before it sends traffic.
  get "/up", NotebookWeb.UpController, :index

  scope "/" do
    pipe_through :mail
    chime_mail("/notifications/mail", app_name: "Notebook")
  end

  # MCP clients: an agent's token (the Agents page), or OAuth when Notebook
  # settings turn it on (NotebookWeb.MCPEndpoint).
  match :*, "/mcp", NotebookWeb.MCPEndpoint, []

  # The OAuth server's discovery, its token API, and the consent page for
  # a person signed in (NotebookWeb.MCP.Subject).
  scope "/" do
    pipe_through :mcp_oauth
    sake_well_known()
  end

  scope "/oauth" do
    pipe_through [:api, :mcp_oauth]
    sake_oauth_api()
  end

  scope "/oauth" do
    pipe_through [:browser, :mcp_oauth, :require_authenticated_user]
    sake_oauth_authorize()
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
      live "/agents/:id", AgentMemoryLive, :show
    end
  end

  # The files of the pages (Storehouse), from the store that has each: for
  # those signed in, and anyone's of a published page.
  scope "/" do
    pipe_through [:browser, NotebookWeb.Plugs.Uploads]
    get "/uploads/kotoba/*key", NotebookWeb.Plugs.Files, []
  end

  # Other scopes may use custom stacks.
  # scope "/api", NotebookWeb do
  #   pipe_through :api
  # end

  ## Authentication routes

  scope "/", NotebookWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [
        {NotebookWeb.UserAuth, :require_authenticated},
        Chime.Live,
        {Jumon.Live, NotebookWeb.Commands}
      ] do
      live "/account/settings", UserLive.Settings, :profile
      live "/account/settings/profile", UserLive.Settings, :profile
      live "/account/settings/password", UserLive.Settings, :password
      live "/account/settings/notifications", UserLive.Settings, :notifications
      live "/notebook/settings", AdminLive, :people
      live "/notebook/settings/people", AdminLive, :people
      live "/notebook/settings/agents", AdminLive, :agents
      live "/notebook/settings/bots", BotsLive, :index
      live "/notebook/settings/files", AdminLive, :files
      live "/notebook/settings/publishing", AdminLive, :publishing
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

  # The open-source libraries the notebook is made with, for anyone.
  scope "/", NotebookWeb do
    pipe_through :browser
    get "/made-with", PageController, :made_with
  end

  # Last: every path the notebook has no route for is a published page's,
  # or no one's (a 404).
  scope "/", NotebookWeb do
    pipe_through :public

    live_session :public,
      root_layout: {NotebookWeb.Layouts, :public_root},
      on_mount: [Masu.Live] do
      live "/*path", PublicLive, :show
    end
  end
end
