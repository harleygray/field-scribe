defmodule FieldScribe.Repo.Migrations.CreateReports do
  use Ecto.Migration

  def change do
    create table(:reports, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, :string, null: false
      add :supervisor, :string, null: false
      add :report_type, :string, null: false
      add :audio_path, :string
      add :audio_deleted_at, :utc_datetime
      add :transcript, :text
      add :structured_data, :map
      add :status, :string, null: false, default: "received"
      add :error_log, {:array, :map}, null: false, default: []
      add :sheet_row_url, :string
      add :drive_audio_url, :string

      timestamps(type: :utc_datetime)
    end

    create index(:reports, [:status])
    create index(:reports, [:project_id, :inserted_at])
  end
end
