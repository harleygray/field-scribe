defmodule FieldScribe.Workers.ReportPipelineTest do
  use FieldScribe.DataCase, async: true

  import Mox
  setup :verify_on_exit!

  alias FieldScribe.{Reports, Storage}
  alias FieldScribe.Workers.ReportPipeline

  setup do
    {:ok, report} =
      Reports.create_report(%{
        "project_id" => "bridgeman-downs",
        "supervisor" => "Perry",
        "report_type" => "daily_progress"
      })

    audio_path = Storage.path_for(report.id)
    File.mkdir_p!(Storage.uploads_dir())
    File.write!(audio_path, "fake audio bytes")
    {:ok, report} = Reports.update_status(report, :received, %{audio_path: audio_path})

    on_exit(fn -> File.rm(audio_path) end)

    %{report: report}
  end

  test "happy path: transcribes, extracts, posts to Apps Script (skipped when URL unset)", %{
    report: report
  } do
    expect(FieldScribe.AI.OpenAIMock, :transcribe, fn _path ->
      {:ok, "Hello it's Perry from Bridgeman Downs"}
    end)

    expect(FieldScribe.AI.OpenAIMock, :extract, fn _transcript, :daily_progress ->
      {:ok,
       %{
         "work_completed" => ["Installed trees"],
         "percent_complete" => 60,
         "crew_size" => 3,
         "weather_impact" => "minor_delay",
         "weather_notes" => "wet soil",
         "blockers" => [],
         "materials_used" => [],
         "materials_needed" => [],
         "tomorrow_plan" => nil,
         "raw_transcript" => "Hello it's Perry from Bridgeman Downs"
       }}
    end)

    # APPS_SCRIPT_WEBHOOK_URL is "" in test → AppsScript.post returns {:skipped, :no_url}
    # which short-circuits to :complete.
    assert :ok = perform_job(ReportPipeline, %{"report_id" => report.id})

    reloaded = Reports.get!(report.id)
    assert reloaded.status == "complete"
    assert reloaded.transcript == "Hello it's Perry from Bridgeman Downs"
    assert reloaded.structured_data["percent_complete"] == 60
  end

  test "transcribe failure marks the report failed and adds an error_log entry", %{report: report} do
    expect(FieldScribe.AI.OpenAIMock, :transcribe, fn _path -> {:error, :boom} end)

    assert {:error, _} = perform_job(ReportPipeline, %{"report_id" => report.id})

    reloaded = Reports.get!(report.id)
    assert reloaded.status == "failed"
    assert [%{"kind" => "pipeline_failed"} | _] = reloaded.error_log
  end

  defp perform_job(worker_mod, args) do
    job = %Oban.Job{
      args: args,
      attempt: 1,
      max_attempts: 5,
      queue: "pipeline",
      worker: to_string(worker_mod)
    }

    worker_mod.perform(job)
  end
end
