defmodule FieldScribe.Reports.Report do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @report_types ~w(daily_progress issue_blocker)

  @statuses ~w(received transcribing extracting writing persisted complete failed)

  schema "reports" do
    field :project_id, :string
    field :supervisor, :string
    field :report_type, :string
    field :audio_path, :string
    field :audio_deleted_at, :utc_datetime
    field :transcript, :string
    field :structured_data, :map
    field :status, :string, default: "received"
    field :error_log, {:array, :map}, default: []
    field :sheet_row_url, :string
    field :drive_audio_url, :string

    timestamps(type: :utc_datetime)
  end

  def report_types, do: @report_types
  def statuses, do: @statuses

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:project_id, :supervisor, :report_type, :audio_path])
    |> validate_required([:project_id, :supervisor, :report_type])
    |> validate_inclusion(:report_type, @report_types)
    |> validate_project_supervisor()
  end

  def status_changeset(report, attrs) do
    report
    |> cast(attrs, [
      :status,
      :transcript,
      :structured_data,
      :sheet_row_url,
      :drive_audio_url,
      :audio_path,
      :audio_deleted_at,
      :error_log
    ])
    |> validate_inclusion(:status, @statuses)
  end

  defp validate_project_supervisor(changeset) do
    project_id = get_field(changeset, :project_id)
    supervisor = get_field(changeset, :supervisor)

    case FieldScribe.Projects.lookup(project_id) do
      nil ->
        add_error(changeset, :project_id, "is not a known project")

      %{supervisors: supervisors} ->
        if supervisor in supervisors do
          changeset
        else
          add_error(changeset, :supervisor, "is not a supervisor on that project")
        end
    end
  end
end
