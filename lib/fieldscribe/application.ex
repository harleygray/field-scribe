defmodule FieldScribe.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    File.mkdir_p!(FieldScribe.Storage.uploads_dir())

    children = [
      FieldScribeWeb.Telemetry,
      FieldScribe.Repo,
      {DNSCluster, query: Application.get_env(:fieldscribe, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: FieldScribe.PubSub},
      {Oban, Application.fetch_env!(:fieldscribe, Oban)},
      FieldScribeWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: FieldScribe.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FieldScribeWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
