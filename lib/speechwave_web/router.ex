defmodule SpeechwaveWeb.Router do
  use SpeechwaveWeb, :router

  import SpeechwaveWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SpeechwaveWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # ---------------------------------------------------------------------------
  # Public routes — no auth required
  # ---------------------------------------------------------------------------

  scope "/", SpeechwaveWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/terms", PageController, :terms
    get "/privacy", PageController, :privacy
    live "/t/:slug", TalkLive
  end

  # ---------------------------------------------------------------------------
  # Authenticated routes — require login
  # ---------------------------------------------------------------------------

  scope "/", SpeechwaveWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{SpeechwaveWeb.UserAuth, :require_authenticated}] do
      live "/dashboard", DashboardLive
      live "/sessions/:id", SessionAnalyticsLive, :show
      live "/sessions/:id/compare/:other_id", SessionAnalyticsLive, :compare
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end
  end

  # ---------------------------------------------------------------------------
  # Auth routes (login — no auth required)
  # ---------------------------------------------------------------------------

  scope "/", SpeechwaveWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{SpeechwaveWeb.UserAuth, :mount_current_scope}] do
      live "/users/log-in", UserLive.Login, :new
      live "/pricing", PricingLive
    end

    get "/users/magic_link/:token", UserSessionController, :magic_link
    delete "/users/log-out", UserSessionController, :delete
  end

  # OAuth routes — accessible authenticated or not (login + connect flows)
  scope "/auth", SpeechwaveWeb do
    pipe_through :browser

    get "/:provider", UserSessionController, :oauth_authorize
    get "/:provider/callback", UserSessionController, :oauth_callback
  end

  if Application.compile_env(:speechwave, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end

    scope "/dev", SpeechwaveWeb do
      pipe_through :browser
      live_dashboard "/dashboard", metrics: SpeechwaveWeb.Telemetry
      get "/login", DevLoginController, :index
      post "/login", DevLoginController, :create
    end
  end
end
