defmodule FieldScribe.Storage do
  @moduledoc """
  Local-filesystem storage for uploaded audio. The recorder hook posts a
  multipart blob, the controller copies it to `priv/uploads/<id>.webm`,
  Apps Script later downloads it via an HMAC-signed URL, and the audio
  retention worker eventually deletes the file (the row stays).

  All file operations route through this module so that switching to S3
  or Tigris later is a single-module change.
  """

  @ext ".webm"

  @spec uploads_dir :: Path.t()
  def uploads_dir do
    Application.app_dir(:fieldscribe, "priv/uploads")
  end

  @spec path_for(String.t()) :: Path.t()
  def path_for(report_id) do
    Path.join(uploads_dir(), report_id <> @ext)
  end

  @doc "Move an uploaded `Plug.Upload` into the report's slot."
  @spec store(String.t(), Path.t()) :: {:ok, Path.t()} | {:error, term()}
  def store(report_id, source_path) do
    File.mkdir_p!(uploads_dir())
    target = path_for(report_id)

    case File.cp(source_path, target) do
      :ok -> {:ok, target}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec delete(String.t()) :: :ok
  def delete(report_id) do
    _ = File.rm(path_for(report_id))
    :ok
  end

  @spec exists?(String.t()) :: boolean()
  def exists?(report_id), do: File.exists?(path_for(report_id))
end
