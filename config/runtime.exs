import Config
import Dotenvy

# Load .env files (gitignored) and OS env into the runtime config in priority order.
# Last source wins, so OS env beats .env.<env> beats .env.
source!([".env", ".env.#{config_env()}", System.get_env()])

# ---------------------------------------------------------------------------
# Database — dev / test connect through a `fly proxy 5432 -a <pg-app>` tunnel.
# Prod gets DATABASE_URL set as a Fly secret via `fly postgres attach`.
# ---------------------------------------------------------------------------
if config_env() != :prod do
  config :fieldscribe, FieldScribe.Repo,
    url:
      env!(
        "DATABASE_URL",
        :string,
        "ecto://postgres:postgres@localhost/fieldscribe_#{config_env()}"
      )
end

# ---------------------------------------------------------------------------
# Application secrets — required at runtime in every env so failures surface
# immediately at boot instead of mid-pipeline. Use safe placeholders in test.
# ---------------------------------------------------------------------------
config :fieldscribe,
  openai_api_key: env!("OPENAI_API_KEY", :string, ""),
  apps_script_webhook_url: env!("APPS_SCRIPT_WEBHOOK_URL", :string, ""),
  apps_script_shared_secret: env!("APPS_SCRIPT_SHARED_SECRET", :string, ""),
  audio_retention_days: env!("AUDIO_RETENTION_DAYS", :integer, 14)

# ---------------------------------------------------------------------------
# Releases: PHX_SERVER=true tells the release to actually start the endpoint.
# ---------------------------------------------------------------------------
if System.get_env("PHX_SERVER") do
  config :fieldscribe, FieldScribeWeb.Endpoint, server: true
end

# ---------------------------------------------------------------------------
# Production-only configuration.
# ---------------------------------------------------------------------------
if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :fieldscribe, FieldScribe.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "fieldscribe.fly.dev"
  port = String.to_integer(System.get_env("PORT") || "8080")

  config :fieldscribe, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :fieldscribe, FieldScribeWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base
end
