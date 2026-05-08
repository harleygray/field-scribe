defmodule FieldScribe.Integrations.AppsScriptTest do
  use ExUnit.Case, async: true

  # Apps Script integration tests. The post/1 function requires a live
  # network call so it is not tested here; see report_pipeline_test.exs
  # for the happy path (APPS_SCRIPT_WEBHOOK_URL="" → :skipped path).
end
