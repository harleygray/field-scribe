ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(FieldScribe.Repo, :manual)

Mox.defmock(FieldScribe.AI.OpenAIMock, for: FieldScribe.AI.OpenAIBehaviour)
Application.put_env(:fieldscribe, :openai_client, FieldScribe.AI.OpenAIMock)
