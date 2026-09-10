defmodule PtyLab.ExperimentTest do
  use ExUnit.Case

  test "missing evidence is execution failure, never a behavioral mismatch" do
    cells = [%{session: %{outcome: "helper_error"}, observation: %{error: "missing receipt"}}]
    assert {"execution_failure", _} = PtyLab.Experiment.compare(cells, "hello\n")
  end

  test "ls requires horizontal layout, not just terminal newline conversion" do
    assert {"pass", _} =
             PtyLab.Experiment.compare(ls_cells("alpha\tbravo\tcharlie\r\n"), "", "ls")

    assert {"mismatch", %{pty_output: false}} =
             PtyLab.Experiment.compare(ls_cells("alpha\r\nbravo\r\ncharlie\r\n"), "", "ls")
  end

  test "ls layout cannot pass with changed task content" do
    [pipe, pty] = ls_cells("alpha bravo charlie\r\n")
    changed = put_in(pty, [:observation, :header, "spec", "argv"], ["-C"])

    assert {"mismatch", %{same_definition: false}} =
             PtyLab.Experiment.compare([pipe, changed], "", "ls")
  end

  defp ls_cells(output) do
    for mode <- ["pipe", "slave"] do
      %{
        session: %{
          outcome: "completed",
          receipt_status: "sealed",
          child_exit: %{"code" => 0, "signal" => :null}
        },
        requested_input_hex: "",
        observation: %{
          analysis: %{classification: "complete", integrity: "verified", metadata_complete: true},
          header: %{
            "spec" => %{"attachment" => mode, "argv" => []},
            "executable" => %{"sha256" => "subject"},
            "helper" => %{"sha256" => "helper"},
            "environment_sha256" => "env",
            "requested_topology" => %{}
          },
          streams_hex: %{
            "stdout" => Base.encode16("alpha\nbravo\ncharlie\n"),
            "stderr" => "",
            "input_written" => "",
            "pty_output" => Base.encode16(output)
          }
        }
      }
    end
  end
end
