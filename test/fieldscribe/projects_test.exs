defmodule FieldScribe.ProjectsTest do
  use ExUnit.Case, async: true

  alias FieldScribe.Projects

  test "list/0 returns the configured projects" do
    projects = Projects.list()
    assert is_list(projects)
    assert Enum.any?(projects, &(&1.id == "bridgeman-downs"))
  end

  test "lookup/1 finds a project by id" do
    assert %{name: "Bridgeman Downs"} = Projects.lookup("bridgeman-downs")
  end

  test "lookup/1 returns nil for an unknown id" do
    assert Projects.lookup("not-a-real-project") == nil
  end

  test "supervisors_for/1 returns the project's supervisors" do
    assert "Perry" in Projects.supervisors_for("bridgeman-downs")
  end

  test "supervisors_for/1 returns [] for an unknown project" do
    assert Projects.supervisors_for("nope") == []
  end
end
