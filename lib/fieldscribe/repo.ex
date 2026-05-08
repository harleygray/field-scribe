defmodule FieldScribe.Repo do
  use Ecto.Repo,
    otp_app: :fieldscribe,
    adapter: Ecto.Adapters.Postgres
end
