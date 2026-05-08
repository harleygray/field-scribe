defmodule FieldScribe.AI.OpenAIBehaviour do
  @moduledoc """
  Behaviour both the real OpenAI client and the test Mox double implement.
  Switched via `config :fieldscribe, :openai_client, ...`.
  """

  @callback transcribe(audio_path :: Path.t()) ::
              {:ok, String.t()} | {:error, term()}

  @callback extract(transcript :: String.t(), report_type :: :daily_progress | :issue_blocker) ::
              {:ok, map()} | {:error, term()}
end
