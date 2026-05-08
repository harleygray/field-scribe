defmodule FieldScribe.AI.Schemas do
  @moduledoc """
  JSON Schemas passed to OpenAI's `response_format: {type: "json_schema",
  strict: true}`. Strict mode requires `additionalProperties: false` and a
  complete `required:` list — including fields the model may legitimately
  set to null. We use union types like `["string", "null"]` for those.
  """

  @doc "Top-level schema spec for the chosen report_type."
  def for(:daily_progress), do: daily_progress()
  def for(:issue_blocker), do: issue_blocker()
  def for(other) when is_binary(other), do: __MODULE__.for(String.to_existing_atom(other))

  defp daily_progress do
    %{
      type: "object",
      additionalProperties: false,
      required: [
        "work_completed",
        "percent_complete",
        "crew_size",
        "weather_impact",
        "weather_notes",
        "blockers",
        "materials_used",
        "materials_needed",
        "tomorrow_plan",
        "raw_transcript"
      ],
      properties: %{
        work_completed: %{type: "array", items: %{type: "string"}},
        percent_complete: %{type: ["integer", "null"], minimum: 0, maximum: 100},
        crew_size: %{type: ["integer", "null"], minimum: 0},
        weather_impact: %{
          type: ["string", "null"],
          enum: ["none", "minor_delay", "major_delay", "stopped_work", nil]
        },
        weather_notes: %{type: ["string", "null"]},
        blockers: %{type: "array", items: %{type: "string"}},
        materials_used: %{type: "array", items: %{type: "string"}},
        materials_needed: %{
          type: "array",
          items: %{
            type: "object",
            additionalProperties: false,
            required: ["item", "quantity", "unit", "urgency"],
            properties: %{
              item: %{type: "string"},
              quantity: %{type: ["number", "null"]},
              unit: %{type: ["string", "null"]},
              urgency: %{
                type: ["string", "null"],
                enum: ["today", "this_week", "next_week", "no_rush", nil]
              }
            }
          }
        },
        tomorrow_plan: %{type: ["string", "null"]},
        raw_transcript: %{type: "string"}
      }
    }
  end

  defp issue_blocker do
    %{
      type: "object",
      additionalProperties: false,
      required: [
        "issue_summary",
        "severity",
        "affected_work",
        "requested_action",
        "deadline_implication",
        "raw_transcript"
      ],
      properties: %{
        issue_summary: %{type: "string"},
        severity: %{type: ["string", "null"], enum: ["low", "medium", "high", "critical", nil]},
        affected_work: %{type: "array", items: %{type: "string"}},
        requested_action: %{type: ["string", "null"]},
        deadline_implication: %{type: ["string", "null"]},
        raw_transcript: %{type: "string"}
      }
    }
  end
end
