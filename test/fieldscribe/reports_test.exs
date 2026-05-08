defmodule FieldScribe.ReportsTest do
  use FieldScribe.DataCase, async: true

  alias FieldScribe.Reports

  describe "create_report/1" do
    test "creates a daily progress report and broadcasts" do
      Phoenix.PubSub.subscribe(FieldScribe.PubSub, Reports.feed_topic())

      assert {:ok, report} =
               Reports.create_report(%{
                 "project_id" => "bridgeman-downs",
                 "supervisor" => "Perry",
                 "report_type" => "daily_progress"
               })

      assert report.status == "received"
      assert_receive {:report_status, %{id: id}}, 500
      assert id == report.id
    end

    test "rejects an unknown project" do
      assert {:error, changeset} =
               Reports.create_report(%{
                 "project_id" => "nope",
                 "supervisor" => "Perry",
                 "report_type" => "daily_progress"
               })

      assert "is not a known project" in errors_on(changeset).project_id
    end

    test "rejects a supervisor that doesn't belong to the project" do
      assert {:error, changeset} =
               Reports.create_report(%{
                 "project_id" => "bridgeman-downs",
                 "supervisor" => "Sam",
                 "report_type" => "daily_progress"
               })

      assert "is not a supervisor on that project" in errors_on(changeset).supervisor
    end

    test "rejects an unknown report_type" do
      assert {:error, changeset} =
               Reports.create_report(%{
                 "project_id" => "bridgeman-downs",
                 "supervisor" => "Perry",
                 "report_type" => "weekly_summary"
               })

      assert errors_on(changeset).report_type != []
    end
  end

  describe "update_status/3" do
    test "updates status and broadcasts on per-report topic" do
      {:ok, report} =
        Reports.create_report(%{
          "project_id" => "bridgeman-downs",
          "supervisor" => "Perry",
          "report_type" => "daily_progress"
        })

      Phoenix.PubSub.subscribe(FieldScribe.PubSub, Reports.report_topic(report.id))

      {:ok, updated} = Reports.update_status(report, :transcribing, %{transcript: "hello"})
      assert updated.status == "transcribing"
      assert updated.transcript == "hello"
      assert_receive {:report_status, %{status: "transcribing"}}, 500
    end
  end
end
