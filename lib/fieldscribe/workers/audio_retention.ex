defmodule FieldScribe.Workers.AudioRetention do
  @moduledoc """
  Daily Oban Cron job that deletes local audio files for `:complete`
  reports older than the configured retention TTL (default 14 days).
  The report row is preserved — only the file bytes go.

  Failed reports are intentionally left alone: they may need the audio
  for manual recovery.
  """

  use Oban.Worker, queue: :retention, max_attempts: 1

  import Ecto.Query
  require Logger

  alias FieldScribe.{Repo, Storage}
  alias FieldScribe.Reports.Report

  @impl Oban.Worker
  def perform(_job) do
    days = Application.get_env(:fieldscribe, :audio_retention_days, 14)
    cutoff = DateTime.utc_now() |> DateTime.add(-days * 86_400, :second)

    stale =
      Report
      |> where([r], r.status == "complete")
      |> where([r], not is_nil(r.audio_path))
      |> where([r], r.inserted_at < ^cutoff)
      |> select([r], r.id)
      |> Repo.all()

    Logger.info("[audio_retention] sweeping #{length(stale)} report(s) older than #{days}d")

    Enum.each(stale, &purge/1)

    :ok
  end

  defp purge(report_id) do
    Storage.delete(report_id)

    Repo.update_all(
      from(r in Report, where: r.id == ^report_id),
      set: [audio_path: nil, audio_deleted_at: DateTime.utc_now() |> DateTime.truncate(:second)]
    )
  end
end
