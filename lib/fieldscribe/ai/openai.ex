defmodule FieldScribe.AI.OpenAI do
  @moduledoc """
  Live OpenAI client. Two functions:
    * `transcribe/1` — Whisper-1 over `/v1/audio/transcriptions`
    * `extract/2` — `gpt-4.1-mini` over `/v1/chat/completions` with a
      `response_format: {type: "json_schema", strict: true}` schema.

  The strict-mode schemas live in `FieldScribe.AI.Schemas`. The system
  prompts live alongside `extract/2` in this module — short and focused on
  "extract only what was said; null for missing; concrete over abstract."
  """

  @behaviour FieldScribe.AI.OpenAIBehaviour

  @transcriptions_url "https://api.openai.com/v1/audio/transcriptions"
  @chat_url "https://api.openai.com/v1/chat/completions"
  @transcription_model "whisper-1"
  @extraction_model "gpt-4.1-mini"
  @timeout_ms 60_000

  @impl true
  def transcribe(audio_path) when is_binary(audio_path) do
    case Req.post(@transcriptions_url,
           auth: {:bearer, api_key()},
           form_multipart: [
             file: File.stream!(audio_path, 64 * 1024, []),
             model: @transcription_model,
             response_format: "json"
           ],
           receive_timeout: @timeout_ms,
           retry: :transient
         ) do
      {:ok, %Req.Response{status: 200, body: %{"text" => text}}} ->
        {:ok, text}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:openai_status, status, body}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  @impl true
  def extract(transcript, report_type)
      when is_binary(transcript) and report_type in [:daily_progress, :issue_blocker] do
    schema = FieldScribe.AI.Schemas.for(report_type)

    payload = %{
      model: @extraction_model,
      messages: [
        %{role: "system", content: system_prompt(report_type)},
        %{role: "user", content: transcript}
      ],
      response_format: %{
        type: "json_schema",
        json_schema: %{name: "report", schema: schema, strict: true}
      }
    }

    case Req.post(@chat_url,
           auth: {:bearer, api_key()},
           json: payload,
           receive_timeout: @timeout_ms,
           retry: :transient
         ) do
      {:ok,
       %Req.Response{
         status: 200,
         body: %{"choices" => [%{"message" => %{"content" => json}} | _]}
       }} ->
        case Jason.decode(json) do
          {:ok, map} -> {:ok, map}
          {:error, reason} -> {:error, {:json_decode, reason, json}}
        end

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:openai_status, status, body}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  defp api_key do
    case Application.fetch_env!(:fieldscribe, :openai_api_key) do
      "" -> raise "OPENAI_API_KEY is not set"
      key -> key
    end
  end

  defp system_prompt(:daily_progress) do
    """
    You extract structured daily-progress reports from a landscape construction
    site supervisor's voice memo transcript.

    Rules:
    - Only include facts the supervisor actually said. Use null for fields
      they did not mention. Do not infer or invent.
    - Prefer concrete details ("two pallets of mulch") over abstract ones
      ("some mulch").
    - `work_completed` and `blockers` are short bullets in the supervisor's
      own words.
    - `raw_transcript` must contain the original transcript verbatim.
    """
  end

  defp system_prompt(:issue_blocker) do
    """
    You extract a structured issue/blocker report from a landscape
    construction site supervisor's voice memo transcript.

    Rules:
    - Only include facts the supervisor actually said. Use null for fields
      they did not mention. Do not infer or invent.
    - `issue_summary` is one sentence, factual.
    - `severity` reflects what the supervisor actually conveys, not what
      you'd guess from the topic.
    - `raw_transcript` must contain the original transcript verbatim.
    """
  end
end
