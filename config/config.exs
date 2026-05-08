# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :fieldscribe,
  namespace: FieldScribe,
  ecto_repos: [FieldScribe.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# Project ↔ supervisor list. Hardcoded for the MVP — promote to an admin
# screen + DB table once there's a second team using this.
config :fieldscribe, :projects, [
  %{
    id: "bridgeman-downs",
    name: "Bridgeman Downs",
    supervisors: ["Will", "Jack", "Harley"]
  },
  %{
    id: "kenmore-hills",
    name: "Kenmore Hills",
    supervisors: ["Will", "Jack", "Harley"]
  }
]

# OpenAI client is swapped to a Mox stub in test/test_helper.exs.
config :fieldscribe, :openai_client, FieldScribe.AI.OpenAI

# Oban — durable pipeline + daily audio retention sweep.
config :fieldscribe, Oban,
  repo: FieldScribe.Repo,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Cron,
     crontab: [
       {"17 3 * * *", FieldScribe.Workers.AudioRetention}
     ]}
  ],
  queues: [pipeline: 5, retention: 1]

# Configure the endpoint
config :fieldscribe, FieldScribeWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: FieldScribeWeb.ErrorHTML, json: FieldScribeWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: FieldScribe.PubSub,
  live_view: [signing_salt: "k48CSuHD"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :fieldscribe, FieldScribe.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  fieldscribe: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  fieldscribe: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
