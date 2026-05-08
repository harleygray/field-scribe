defmodule FieldScribeWeb.Router do
  use FieldScribeWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FieldScribeWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", FieldScribeWeb do
    pipe_through :browser

    live "/", FieldScribeLive, :index
  end

  scope "/api", FieldScribeWeb do
    pipe_through :api

    post "/reports", Api.ReportsController, :create
    get "/reports/:id", Api.ReportsController, :show
  end

  if Application.compile_env(:fieldscribe, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: FieldScribeWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
