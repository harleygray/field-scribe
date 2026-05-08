defmodule FieldScribe.Projects do
  @moduledoc """
  Read-only access to the project ↔ supervisor list configured at compile time
  in `config :fieldscribe, :projects`.
  """

  @spec list :: [map()]
  def list, do: Application.get_env(:fieldscribe, :projects, [])

  @spec lookup(String.t() | nil) :: map() | nil
  def lookup(nil), do: nil
  def lookup(project_id), do: Enum.find(list(), &(&1.id == project_id))

  @spec supervisors_for(String.t()) :: [String.t()]
  def supervisors_for(project_id) do
    case lookup(project_id) do
      %{supervisors: supervisors} -> supervisors
      _ -> []
    end
  end

  @spec project_options :: [{String.t(), String.t()}]
  def project_options do
    Enum.map(list(), &{&1.name, &1.id})
  end
end
