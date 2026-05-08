defmodule FieldScribe.Reports do
  @moduledoc """
  Context for the `reports` table. Owns persistence and the per-report +
  feed-level PubSub broadcasts that drive the LiveView.
  """

  import Ecto.Query
  alias FieldScribe.Repo
  alias FieldScribe.Reports.Report

  @feed_topic "reports:feed"

  def feed_topic, do: @feed_topic
  def report_topic(report_id), do: "reports:" <> report_id

  @spec create_report(map()) :: {:ok, Report.t()} | {:error, Ecto.Changeset.t()}
  def create_report(attrs) do
    case attrs |> Report.create_changeset() |> Repo.insert() do
      {:ok, report} ->
        broadcast(report, :created)
        {:ok, report}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @spec get(String.t()) :: Report.t() | nil
  def get(id), do: Repo.get(Report, id)

  @spec get!(String.t()) :: Report.t()
  def get!(id), do: Repo.get!(Report, id)

  @spec list_recent(integer()) :: [Report.t()]
  def list_recent(limit \\ 25) do
    Report
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @spec list_by_ids([String.t()]) :: [Report.t()]
  def list_by_ids([]), do: []

  def list_by_ids(ids) when is_list(ids) do
    Report
    |> where([r], r.id in ^ids)
    |> Repo.all()
  end

  @doc """
  Update the report's status and any other fields, then broadcast on both
  the per-report and feed topics so subscribed LiveViews can update.
  """
  @spec update_status(Report.t(), atom() | String.t(), map()) ::
          {:ok, Report.t()} | {:error, Ecto.Changeset.t()}
  def update_status(report, status, extra_attrs \\ %{}) do
    attrs = Map.merge(extra_attrs, %{status: to_string(status)})

    case report |> Report.status_changeset(attrs) |> Repo.update() do
      {:ok, updated} ->
        broadcast(updated, :status)
        {:ok, updated}

      err ->
        err
    end
  end

  @doc """
  Append a structured error entry to the report's error_log array. Used by
  the pipeline worker to record non-fatal warnings (e.g. malformed JSON
  fallbacks) without leaving the row in :failed.
  """
  @spec append_error(Report.t(), map()) :: {:ok, Report.t()} | {:error, term()}
  def append_error(report, error_map) when is_map(error_map) do
    entry = Map.put_new(error_map, "at", DateTime.utc_now() |> DateTime.to_iso8601())

    report
    |> Report.status_changeset(%{error_log: report.error_log ++ [entry]})
    |> Repo.update()
  end

  defp broadcast(report, _kind) do
    Phoenix.PubSub.broadcast(
      FieldScribe.PubSub,
      @feed_topic,
      {:report_status, report}
    )

    Phoenix.PubSub.broadcast(
      FieldScribe.PubSub,
      report_topic(report.id),
      {:report_status, report}
    )

    :ok
  end
end
