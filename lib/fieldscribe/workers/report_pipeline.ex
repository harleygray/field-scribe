defmodule FieldScribe.Workers.ReportPipeline do
  @moduledoc """
  The single Oban worker that walks a report through its lifecycle.

  Status transitions, each broadcast on the report's PubSub topic:

      received → transcribing → extracting → writing → persisted → complete

  Failures jump to `:failed` and Oban retries with exponential backoff.
  Idempotency: the report ID is the job's unique args, and Apps Script
  no-ops on a duplicate via its `_FieldScribeSeen` ledger.

  Apps Script returns the Sheet row URL and Drive audio URL synchronously
  in the POST response body. The worker reads them directly and advances
  the report to `:persisted` → `:complete` without a separate callback.
  """

  use Oban.Worker, queue: :pipeline, max_attempts: 5

  require Logger

  alias FieldScribe.{Reports, Storage}
  alias FieldScribe.Integrations.AppsScript

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"report_id" => report_id}}) do
    case Reports.get(report_id) do
      nil ->
        {:cancel, :report_not_found}

      report ->
        run(report)
    end
  end

  defp run(report) do
    with {:ok, report} <- transcribe(report),
         {:ok, report} <- extract(report),
         {:ok, _report} <- write_to_apps_script(report) do
      :ok
    else
      {:error, reason} ->
        mark_failed(report, reason)
        {:error, reason}
    end
  end

  defp transcribe(report) do
    {:ok, report} = Reports.update_status(report, :transcribing)

    cond do
      not is_binary(report.audio_path) ->
        {:error, :no_audio_path}

      not Storage.exists?(report.id) ->
        {:error, :audio_missing}

      true ->
        case openai_client().transcribe(report.audio_path) do
          {:ok, text} ->
            Reports.update_status(report, :transcribing, %{transcript: text})

          {:error, reason} ->
            {:error, {:transcribe_failed, reason}}
        end
    end
  end

  defp extract(report) do
    {:ok, report} = Reports.update_status(report, :extracting)

    type =
      case report.report_type do
        "daily_progress" -> :daily_progress
        "issue_blocker" -> :issue_blocker
      end

    case openai_client().extract(report.transcript || "", type) do
      {:ok, structured} ->
        Reports.update_status(report, :extracting, %{structured_data: structured})

      {:error, {:json_decode, reason, raw}} ->
        # Strict JSON-Schema in OpenAI should make this rare. Record the
        # malformed output but don't fail the pipeline — the row still has
        # the transcript and Apps Script can write a row using transcript
        # only.
        {:ok, _} =
          Reports.append_error(report, %{
            "stage" => "extracting",
            "kind" => "json_decode",
            "reason" => inspect(reason),
            "raw" => raw
          })

        Reports.update_status(report, :extracting, %{structured_data: %{}})

      {:error, reason} ->
        {:error, {:extract_failed, reason}}
    end
  end

  defp write_to_apps_script(report) do
    {:ok, report} = Reports.update_status(report, :writing)
    Logger.info("[Pipeline] Calling AppsScript for report #{report.id}")

    result = AppsScript.post(report)
    Logger.info("[Pipeline] AppsScript result: #{inspect(result)}")

    case result do
      {:ok, body} when is_map(body) ->
        attrs = maybe_put(%{}, :sheet_row_url, body["sheet_row_url"])
        {:ok, report} = Reports.update_status(report, :persisted, attrs)
        Reports.update_status(report, :complete)

      {:ok, unexpected} ->
        Logger.warning("[Pipeline] Unexpected Apps Script body type: #{inspect(unexpected)}")
        {:ok, report} = Reports.update_status(report, :persisted)
        Reports.update_status(report, :complete)

      {:skipped, :no_url} ->
        {:ok, _} =
          Reports.append_error(report, %{
            "stage" => "writing",
            "kind" => "apps_script_skipped",
            "reason" => "APPS_SCRIPT_WEBHOOK_URL is unset"
          })

        Reports.update_status(report, :complete)

      {:error, reason} ->
        {:error, {:apps_script_failed, reason}}
    end
  rescue
    e ->
      Logger.error(
        "[Pipeline] Exception in write_to_apps_script: #{Exception.message(e)}\n" <>
          Exception.format_stacktrace(__STACKTRACE__)
      )

      {:error, {:apps_script_exception, Exception.message(e)}}
  end

  defp maybe_put(map, _k, nil), do: map
  defp maybe_put(map, _k, ""), do: map
  defp maybe_put(map, k, v), do: Map.put(map, k, v)

  defp mark_failed(report, reason) do
    {:ok, _} =
      Reports.append_error(report, %{
        "stage" => report.status,
        "kind" => "pipeline_failed",
        "reason" => inspect(reason)
      })

    Reports.update_status(report, :failed)
  end

  defp openai_client do
    Application.get_env(:fieldscribe, :openai_client, FieldScribe.AI.OpenAI)
  end
end
