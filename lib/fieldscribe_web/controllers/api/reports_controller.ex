defmodule FieldScribeWeb.Api.ReportsController do
  use FieldScribeWeb, :controller

  alias FieldScribe.{Reports, Storage}
  alias FieldScribe.Workers.ReportPipeline

  @doc """
  Multipart upload endpoint.

  Form fields: project_id, supervisor, report_type, audio (Plug.Upload).
  Returns 202 with `{id, status}`; the LiveView starts watching that
  report's PubSub topic immediately.
  """
  def create(conn, params) do
    audio = params["audio"]

    with {:upload, %Plug.Upload{} = upload} <- {:upload, audio},
         {:ok, report} <-
           Reports.create_report(%{
             "project_id" => params["project_id"],
             "supervisor" => params["supervisor"],
             "report_type" => params["report_type"]
           }),
         {:ok, stored_path} <- Storage.store(report.id, upload.path),
         {:ok, report} <- Reports.update_status(report, :received, %{audio_path: stored_path}),
         {:ok, _job} <- enqueue_pipeline(report.id) do
      conn
      |> put_status(:accepted)
      |> json(%{id: report.id, status: report.status})
    else
      {:upload, _} ->
        conn |> put_status(:bad_request) |> json(%{error: "audio file is required"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation_failed", details: format_errors(changeset)})

      {:error, reason} ->
        conn |> put_status(:internal_server_error) |> json(%{error: inspect(reason)})
    end
  end

  def show(conn, %{"id" => id}) do
    case Reports.get(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      report ->
        json(conn, render_report(report))
    end
  end

  defp enqueue_pipeline(report_id) do
    %{"report_id" => report_id}
    |> ReportPipeline.new()
    |> Oban.insert()
  end

  defp render_report(report) do
    %{
      id: report.id,
      project_id: report.project_id,
      supervisor: report.supervisor,
      report_type: report.report_type,
      status: report.status,
      transcript: report.transcript,
      structured_data: report.structured_data,
      sheet_row_url: report.sheet_row_url,
      drive_audio_url: report.drive_audio_url,
      inserted_at: report.inserted_at,
      updated_at: report.updated_at
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
  end
end
