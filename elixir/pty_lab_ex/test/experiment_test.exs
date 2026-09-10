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

  test "echo requires exactly its declared configuration change and kernel readback" do
    cells = echo_cells()
    assert {"pass", _} = PtyLab.Experiment.compare(cells, "hello\n", "echo")
    [on, off] = cells
    extra = put_in(off, [:observation, :header, "spec", "terminal", "dimensions", "cols"], 40)

    assert {"mismatch", %{same_definition: false}} =
             PtyLab.Experiment.compare([on, extra], "hello\n", "echo")

    missing = put_in(off, [:observation, :terminal_observations], [])

    assert {"mismatch", %{observed_terminal_configuration: false}} =
             PtyLab.Experiment.compare([on, missing], "hello\n", "echo")

    unchanged =
      put_in(
        off,
        [:observation, :streams_hex, "pty_output"],
        Base.encode16("input> hello\r\nreceived: hello\r\n")
      )

    assert {"mismatch", %{pty_output: false}} =
             PtyLab.Experiment.compare([on, unchanged], "hello\n", "echo")
  end

  test "canonical requires early byte delivery, fixed VMIN and native readback" do
    cells = canonical_cells()
    assert {"pass", _} = PtyLab.Experiment.compare(cells, "h\n", "canonical")
    [on, off] = cells

    late =
      put_in(
        off,
        [:observation, :streams_hex, "pty_output"],
        on.observation.streams_hex["pty_output"]
      )

    assert {"mismatch", %{treatment_output: false}} =
             PtyLab.Experiment.compare([on, late], "h\n", "canonical")

    wrong =
      update_in(
        off,
        [:observation, :header, "spec", "terminal", "termios", "cc"],
        &List.replace_at(&1, 16, 2)
      )

    assert {"mismatch", %{same_definition: false}} =
             PtyLab.Experiment.compare([on, wrong], "h\n", "canonical")

    unknown =
      update_in(off, [:observation, :terminal_observations], fn [o] ->
        [Map.delete(o, "canonical_mask")]
      end)

    assert {"mismatch", %{observed_terminal_configuration: false}} =
             PtyLab.Experiment.compare([on, unknown], "h\n", "canonical")
  end

  defp canonical_cells do
    Enum.zip(ls_cells(""), [true, false])
    |> Enum.map(fn {cell, canonical} ->
      cc = List.duplicate(0, 18) |> List.replace_at(16, 1)

      config = %{
        "termios" => %{
          "echo" => false,
          "canonical" => canonical,
          "lflag" => if(canonical, do: 256, else: 0),
          "cc" => cc
        },
        "dimensions" => %{"cols" => 80}
      }

      cell
      |> Map.put(:requested_input_hex, Base.encode16("h\n"))
      |> put_in([:observation, :header, "spec"], %{"attachment" => "slave", "terminal" => config})
      |> put_in([:observation, :streams_hex, "input_written"], Base.encode16("h\n"))
      |> put_in(
        [:observation, :streams_hex, "pty_output"],
        Base.encode16(
          "READY\r\nWINDOW " <> if(canonical, do: "NONE", else: "68") <> "\r\nFINAL 680a\r\n"
        )
      )
      |> update_in(
        [:observation],
        &Map.put(&1, :terminal_observations, [
          %{
            "phase" => "slave_before_spawn",
            "echo_mask" => 8,
            "canonical_mask" => 256,
            "vmin_index" => 16,
            "vtime_index" => 17,
            "configuration" => config
          }
        ])
      )
    end)
  end

  defp echo_cells do
    Enum.zip(ls_cells(""), [true, false])
    |> Enum.map(fn {cell, echo} ->
      config = %{
        "termios" => %{"echo" => echo, "lflag" => if(echo, do: 8, else: 0)},
        "dimensions" => %{"cols" => 80}
      }

      cell
      |> Map.put(:requested_input_hex, Base.encode16("hello\n"))
      |> put_in([:observation, :header, "spec"], %{"attachment" => "slave", "terminal" => config})
      |> put_in([:observation, :streams_hex, "input_written"], Base.encode16("hello\n"))
      |> put_in(
        [:observation, :streams_hex, "pty_output"],
        Base.encode16(
          if(echo,
            do: "input> hello\r\nreceived: hello\r\n",
            else: "input> received: hello\r\n"
          )
        )
      )
      |> update_in(
        [:observation],
        &Map.put(&1, :terminal_observations, [
          %{"phase" => "slave_before_spawn", "echo_mask" => 8, "configuration" => config}
        ])
      )
    end)
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
