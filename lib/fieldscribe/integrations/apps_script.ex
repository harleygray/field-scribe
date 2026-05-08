defmodule FieldScribe.Integrations.AppsScript do
  @moduledoc """
  Outbound seam to the Apps Script Web App that writes structured report
  data to a shared Google Sheet.

  The Apps Script source lives at `priv/apps_script/Code.gs`. Phoenix POSTs
  the report payload; Apps Script appends a row and returns the Sheet row URL
  synchronously in the response body.
  """

  require Logger

  @timeout_ms 60_000

  @spec post(FieldScribe.Reports.Report.t()) ::
          {:ok, map()} | {:skipped, :no_url} | {:error, term()}
  def post(%FieldScribe.Reports.Report{} = report) do
    case Application.fetch_env!(:fieldscribe, :apps_script_webhook_url) do
      "" ->
        {:skipped, :no_url}

      url ->
        post_following_redirect(url, payload(report))
    end
  end

  # Apps Script's /exec URL returns a 302 redirect before processing the
  # request. Standard HTTP clients convert POST→GET when following 302s,
  # which causes a 400. We disable auto-redirect on the first request and
  # re-POST manually to the Location header.
  defp post_following_redirect(url, body) do
    Logger.info("[AppsScript] POST #{url}")

    case Req.post(url, json: body, receive_timeout: @timeout_ms, redirect: false) do
      {:ok, %Req.Response{status: status, headers: headers}} when status in [301, 302, 303, 307, 308] ->
        case Map.get(headers, "location") do
          [location | _] ->
            Logger.info("[AppsScript] Redirect → #{location}")
            result = Req.get(location, receive_timeout: @timeout_ms, retry: :transient)
            log_response(result)
            handle_response(result)

          _ ->
            Logger.warning("[AppsScript] Redirect with no Location header (status=#{status})")
            {:error, :redirect_missing_location}
        end

      other ->
        log_response(other)
        handle_response(other)
    end
  end

  defp log_response({:ok, %Req.Response{status: status, body: body}}) do
    Logger.info("[AppsScript] Response status=#{status} body=#{inspect(body)}")
  end

  defp log_response({:error, reason}) do
    Logger.warning("[AppsScript] Request error: #{inspect(reason)}")
  end

  defp payload(report) do
    %{
      report_id: report.id,
      project_id: report.project_id,
      supervisor: report.supervisor,
      report_type: report.report_type,
      transcript: report.transcript,
      structured_data: report.structured_data,
      shared_secret: Application.fetch_env!(:fieldscribe, :apps_script_shared_secret)
    }
  end

  defp handle_response({:ok, %Req.Response{status: status} = resp})
       when status in 200..299,
       do: {:ok, resp.body}

  defp handle_response({:ok, %Req.Response{status: status, body: body}}),
    do: {:error, {:apps_script_status, status, body}}

  defp handle_response({:error, exception}), do: {:error, exception}
end
