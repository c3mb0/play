defmodule PtyLab.ExperimentTest do
  use ExUnit.Case

  test "missing evidence is execution failure, never a behavioral mismatch" do
    cells = [%{session: %{outcome: "helper_error"}, observation: %{error: "missing receipt"}}]
    assert {"execution_failure", _} = PtyLab.Experiment.compare(cells, "hello\n")
  end
end
