defmodule PtyLab.Experiment do
  @moduledoc "Bounded matched-pair witnesses over the Erlang session API."

  @doc "Runs declared pairs, preserving raw receipts and writing a separate interpretation."
  def run_hello_pairs(options), do: run_pairs(options, :hello)

  @doc "Runs the predeclared installed ls layout witness with no input."
  def run_ls_pairs(options), do: run_pairs(options, :ls)

  @doc "Runs the predeclared macOS PTY echo-on/echo-off witness."
  def run_echo_pairs(options) do
    unless :os.type() == {:unix, :darwin},
      do: raise(ArgumentError, "macOS terminal fixture required")

    run_pairs(options, :echo)
  end

  @doc "Runs the bounded macOS canonical/byte delivery witness with echo off."
  def run_canonical_pairs(options) do
    unless :os.type() == {:unix, :darwin},
      do: raise(ArgumentError, "macOS terminal fixture required")

    run_pairs(options, :canonical)
  end

  defp run_pairs(options, witness) do
    root = Path.expand(Map.fetch!(options, :root))
    directory = Path.expand(Map.fetch!(options, :directory))
    pairs = Map.get(options, :pairs, 3)
    concurrency = Map.get(options, :max_concurrency, 2)

    unless pairs in 1..100 and concurrency in 1..4,
      do: raise(ArgumentError, "bounded pairs/concurrency required")

    :ok = File.mkdir(directory)
    {:ok, _} = Application.ensure_all_started(:pty_lab)
    config_file = Path.join(root, "receipts/gate-20260910T194539Z/terminal-config.json")
    config_bytes = File.read!(config_file)

    definition = %{
      root: root,
      directory: directory,
      experiment: Map.get(options, :name, "#{witness}_pairs"),
      witness: Atom.to_string(witness),
      pairs: pairs,
      max_concurrency: concurrency,
      order:
        case witness do
          :echo -> ["echo_on", "echo_off"]
          :canonical -> ["canonical_on", "canonical_off"]
          _ -> ["pipe", "slave"]
        end,
      continuation: "continue_remaining_pairs",
      session_deadline_ms: 5000,
      input_delay_ms: if(witness in [:hello, :echo], do: 100, else: 0),
      input_anchor:
        case witness do
          :ls -> "no input"
          :canonical -> "READY: send h; WINDOW line: send newline; probe window 400 ms"
          _ -> "received spawned"
        end,
      expected_input:
        case witness do
          :ls -> ""
          :canonical -> "h\n"
          _ -> "hello\n"
        end,
      retries: 0,
      input_overrides: Map.get(options, :input_overrides, %{}),
      executable_overrides: Map.get(options, :executable_overrides, %{}),
      terminal: :json.decode(config_bytes),
      terminal_config_sha256: hash(config_bytes),
      spec: %{
        "executable" =>
          case witness do
            :ls -> "/bin/ls"
            :canonical -> Path.join(root, "target/debug/byte_witness")
            _ -> Path.join(root, "target/debug/hello_witness")
          end,
        "argv" => [],
        "cwd" =>
          if(witness != :ls, do: root, else: Path.join(root, "experiments/ls_001/fixture")),
        "environment" => %{"PATH" => "/usr/bin:/bin", "LANG" => "C", "TERM" => "xterm-256color"}
      }
    }

    started = System.system_time(:nanosecond)

    results =
      1..pairs
      |> Task.async_stream(fn index -> pair(index, definition) end,
        max_concurrency: concurrency,
        ordered: true,
        timeout: 20_000,
        on_timeout: :kill_task
      )
      |> Enum.with_index(1)
      |> Enum.map(fn
        {{:ok, result}, _index} ->
          result

        {{:exit, reason}, index} ->
          %{
            pair: index,
            outcome: "execution_failure",
            error: inspect(reason),
            cells:
              Enum.map(
                definition.order,
                &%{
                  attachment: &1,
                  receipt: receipt_path(definition, index, &1),
                  observation: "unavailable"
                }
              )
          }
      end)

    counts = Enum.frequencies_by(results, & &1.outcome)

    report = %{
      schema: 1,
      kind: "interpretation",
      definition: definition,
      start_unix_ns: started,
      end_unix_ns: System.system_time(:nanosecond),
      elixir_version: System.version(),
      otp_release: :erlang.system_info(:otp_release) |> List.to_string(),
      counts: counts,
      pairs: results,
      outcome: if(Map.get(counts, "pass", 0) == pairs, do: "pass", else: "anomalies"),
      limits:
        "Declared witness and fixture only; fixed timing policy is not identical scheduling; cleanup results are not OS absence proof"
    }

    report_file = Path.join(directory, "report.json")
    bytes = IO.iodata_to_binary([:json.encode(report), "\n"])
    write_new(report_file, bytes)
    write_new(report_file <> ".sha256", hash(bytes) <> "\n")
    {:ok, report}
  end

  defp pair(index, definition) do
    input = Map.get(definition.input_overrides, index, definition.expected_input)

    unless is_binary(input) and byte_size(input) < 1024 and
             (String.ends_with?(input, "\n") or (definition.witness == "ls" and input == "")),
           do: raise(ArgumentError, "input must be a bounded newline-terminated binary")

    spec =
      definition.spec
      |> Map.put(
        "executable",
        Map.get(definition.executable_overrides, index, definition.spec["executable"])
      )
      |> Map.put("terminal", definition.terminal)

    cells = Enum.map(definition.order, &cell(index, &1, input, spec, definition))
    {outcome, checks} = compare(cells, definition.expected_input, definition.witness)

    %{
      pair: index,
      input_hex: Base.encode16(input),
      cells: cells,
      outcome: outcome,
      checks: checks
    }
  rescue
    error ->
      %{
        pair: index,
        outcome: "execution_failure",
        error: Exception.message(error),
        cells:
          Enum.map(
            definition.order,
            &%{
              attachment: &1,
              receipt: receipt_path(definition, index, &1),
              observation: "unavailable"
            }
          )
      }
  end

  defp cell(index, mode, input, spec, definition) do
    identity = %{
      "run" => Path.basename(definition.directory),
      "experiment" => definition.experiment,
      "cell" => "pair-#{index}/#{mode}",
      "session" => "pair-#{index}-#{mode}"
    }

    receipt = receipt_path(definition, index, mode)

    options = %{
      identity: identity,
      spec: cell_spec(spec, mode),
      helper: Path.join(definition.root, "target/debug/pty_helper") |> String.to_charlist(),
      receipt: String.to_charlist(receipt),
      deadline_ms: definition.session_deadline_ms
    }

    result =
      case :pty_session.start_session(options) do
        {:ok, handle} ->
          input_result =
            cond do
              definition.witness == "canonical" ->
                canonical_input(handle, input)

              input == "" ->
                :no_input

              true ->
                case :pty_session.await_event(handle, "spawned", 1000) do
                  {:ok, _} ->
                    anchor = System.monotonic_time(:nanosecond)

                    :ok =
                      :receipt_writer.event(handle.worker, "input_timing_policy", %{
                        delay_ms: definition.input_delay_ms,
                        anchor: "experiment receives spawned",
                        spawn_received_monotonic_ns: anchor
                      })

                    receive do
                    after
                      definition.input_delay_ms -> :ok
                    end

                    :ok =
                      :receipt_writer.event(handle.worker, "input_timing_observation", %{
                        delay_ns: System.monotonic_time(:nanosecond) - anchor,
                        meaning: "write-request preparation; not OS delivery"
                      })

                    :pty_session.send_input(handle, input)

                  {:error, reason} ->
                    {:error, reason}
                end
            end

          case :pty_session.await_result(handle, 6500) do
            {:ok, session_result} ->
              %{
                outcome: session_result.outcome,
                child_exit: session_result.child_exit,
                receipt_status: Atom.to_string(session_result.receipt_status),
                cleanup: session_result.cleanup,
                details: session_result.details,
                input_request: inspect(input_result)
              }

            {:error, reason} ->
              %{
                outcome: "result_unavailable",
                error: inspect(reason),
                input_request: inspect(input_result)
              }
          end

        {:error, reason} ->
          %{outcome: "start_failure", error: inspect(reason)}
      end

    %{
      identity: identity,
      attachment: cell_spec(spec, mode)["attachment"],
      condition: mode,
      receipt: receipt,
      session: result,
      requested_input_hex: Base.encode16(input),
      observation: read_receipt(receipt)
    }
  end

  defp read_receipt(file) do
    with {:ok, bytes} <- File.read(file), {:ok, seal} <- File.read(file <> ".sha256") do
      analysis = :receipt_recovery.analyze(bytes, {:present, seal})
      events = bytes |> String.split("\n", trim: true) |> Enum.map(&:json.decode/1)
      helper = for %{"event" => "helper_event", "data" => event} <- events, do: event

      streams =
        for stream <- ["stdout", "stderr", "pty_output", "input_written"], into: %{} do
          bytes =
            for %{"event" => ^stream, "data" => %{"hex" => hex}} <- helper,
                into: <<>>,
                do: Base.decode16!(hex, case: :mixed)

          {stream, Base.encode16(bytes)}
        end

      %{
        sha256: hash(bytes),
        analysis: analysis,
        header: hd(events)["data"],
        streams_hex: streams,
        child_exits: for(%{"event" => "child_exit", "data" => data} <- helper, do: data),
        terminal_observations:
          for(%{"event" => "spawned", "data" => data} <- helper, do: data["terminal_observation"])
      }
    else
      {:error, reason} -> %{error: inspect(reason)}
    end
  rescue
    error -> %{error: Exception.message(error)}
  end

  @doc false
  def compare(cells, expected_input, witness \\ "hello") do
    complete =
      Enum.all?(cells, fn c ->
        c.session.outcome == "completed" and c.session[:receipt_status] == "sealed" and
          c.session[:child_exit] == %{"code" => 0, "signal" => :null} and
          get_in(c, [:observation, :analysis, :classification]) == "complete" and
          get_in(c, [:observation, :analysis, :integrity]) == "verified" and
          get_in(c, [:observation, :analysis, :metadata_complete]) == true
      end)

    if complete do
      [pipe, pty] = cells
      a = pipe.observation.header
      b = pty.observation.header
      actual_pipe = Base.decode16!(pipe.observation.streams_hex["stdout"])
      actual_pty = Base.decode16!(pty.observation.streams_hex["pty_output"])

      checks = %{
        same_definition: matched_specs?(a["spec"], b["spec"], witness),
        same_binary: a["executable"]["sha256"] == b["executable"]["sha256"],
        same_helper: a["helper"]["sha256"] == b["helper"]["sha256"],
        same_environment: a["environment_sha256"] == b["environment_sha256"],
        same_topology_policy: a["requested_topology"] == b["requested_topology"],
        same_input: pipe.requested_input_hex == pty.requested_input_hex,
        input_written_matches:
          Enum.all?(
            cells,
            &(&1.requested_input_hex == &1.observation.streams_hex["input_written"])
          ),
        declared_input: pipe.requested_input_hex == Base.encode16(expected_input),
        pipe_output:
          control_matches?(pipe, actual_pipe, expected_input, witness) and
            pipe.observation.streams_hex["stderr"] == "",
        pty_output: pty_matches?(actual_pty, expected_input, witness)
      }

      checks =
        if witness in ["echo", "canonical"] do
          Map.put(
            checks,
            :observed_terminal_configuration,
            Enum.all?(cells, fn c ->
              case c.observation[:terminal_observations] do
                [%{"phase" => "slave_before_spawn", "echo_mask" => 8, "configuration" => config}] ->
                  config == c.observation.header["spec"]["terminal"] and
                    native_axis_matches?(hd(c.observation.terminal_observations), witness)

                _ ->
                  false
              end
            end)
          )
        else
          checks
        end

      checks =
        if witness == "canonical" do
          checks
          |> Map.put(:control_output, checks.pipe_output)
          |> Map.put(:treatment_output, checks.pty_output)
          |> Map.drop([:pipe_output, :pty_output])
        else
          checks
        end

      {if(Enum.all?(checks, fn {_, value} -> value end), do: "pass", else: "mismatch"), checks}
    else
      {"execution_failure", %{sessions_completed_with_verified_zero_exits: false}}
    end
  end

  defp canonical_input(handle, "h\n") do
    with {:ok, "READY\r\n"} <- await_line(handle, "", System.monotonic_time(:millisecond) + 1000),
         :ok <-
           :receipt_writer.event(handle.worker, "canonical_input_policy", %{
             first: "68",
             second: "0a",
             window_ms: 400,
             anchor: "READY then WINDOW line"
           }),
         :ok <- :pty_session.send_input(handle, "h"),
         {:ok, %{"data" => %{"hex" => "68"}}} <-
           :pty_session.await_event(handle, "input_written", 1000),
         {:ok, window} <- await_line(handle, "", System.monotonic_time(:millisecond) + 1000),
         true <- window in ["WINDOW NONE\r\n", "WINDOW 68\r\n"],
         :ok <-
           :receipt_writer.event(handle.worker, "canonical_window_observed", %{
             hex: Base.encode16(window)
           }),
         :ok <- :pty_session.send_input(handle, "\n"),
         {:ok, %{"data" => %{"hex" => "0a"}}} <-
           :pty_session.await_event(handle, "input_written", 1000) do
      :ok
    else
      error -> {:error, {:canonical_input, error}}
    end
  end

  defp canonical_input(_, _), do: {:error, :canonical_input_must_be_h_newline}

  defp await_line(handle, bytes, deadline) do
    cond do
      byte_size(bytes) > 1024 ->
        {:error, :output_limit}

      String.ends_with?(bytes, "\n") ->
        {:ok, bytes}

      System.monotonic_time(:millisecond) >= deadline ->
        {:error, :phase_timeout}

      true ->
        timeout = max(0, deadline - System.monotonic_time(:millisecond))

        case :pty_session.await_event(handle, "pty_output", timeout) do
          {:ok, %{"data" => %{"hex" => hex}}} ->
            await_line(handle, bytes <> Base.decode16!(hex, case: :mixed), deadline)

          error ->
            error
        end
    end
  end

  defp native_axis_matches?(observation, "canonical"),
    do:
      observation["canonical_mask"] == 256 and observation["vmin_index"] == 16 and
        observation["vtime_index"] == 17

  defp native_axis_matches?(_, _), do: true

  defp cell_spec(spec, "canonical_on"), do: cell_spec(spec, "echo_off")

  defp cell_spec(spec, "canonical_off") do
    cell_spec(spec, "canonical_on")
    |> put_in(["terminal", "termios", "canonical"], false)
    |> update_in(["terminal", "termios", "lflag"], &Bitwise.band(&1, Bitwise.bnot(256)))
  end

  defp cell_spec(spec, "echo_on"), do: Map.put(spec, "attachment", "slave")

  defp cell_spec(spec, "echo_off") do
    spec
    |> Map.put("attachment", "slave")
    |> put_in(["terminal", "termios", "echo"], false)
    |> update_in(["terminal", "termios", "lflag"], &Bitwise.band(&1, Bitwise.bnot(8)))
  end

  defp cell_spec(spec, mode), do: Map.put(spec, "attachment", mode)

  defp matched_specs?(on, off, "canonical") do
    t = on["terminal"]["termios"]

    on["attachment"] == "slave" and t["echo"] == false and t["canonical"] == true and
      Bitwise.band(t["lflag"], 8) == 0 and Bitwise.band(t["lflag"], 256) == 256 and
      Enum.at(t["cc"], 16) == 1 and Enum.at(t["cc"], 17) == 0 and
      off == cell_spec(on, "canonical_off")
  end

  defp matched_specs?(on, off, "echo") do
    on["attachment"] == "slave" and on["terminal"]["termios"]["echo"] == true and
      Bitwise.band(on["terminal"]["termios"]["lflag"], 8) == 8 and
      Bitwise.band(on["terminal"]["termios"]["lflag"], 16) == 0 and
      off == cell_spec(on, "echo_off")
  end

  defp matched_specs?(a, b, _), do: Map.delete(a, "attachment") == Map.delete(b, "attachment")

  defp control_matches?(cell, _, "h\n", "canonical"),
    do:
      Base.decode16!(cell.observation.streams_hex["pty_output"]) ==
        "READY\r\nWINDOW NONE\r\nFINAL 680a\r\n"

  defp control_matches?(cell, _, input, "echo"),
    do: pty_matches?(Base.decode16!(cell.observation.streams_hex["pty_output"]), input, "hello")

  defp control_matches?(_, bytes, input, witness), do: pipe_matches?(bytes, input, witness)

  defp pipe_matches?(bytes, _, "ls"), do: bytes == "alpha\nbravo\ncharlie\n"
  defp pipe_matches?(bytes, input, "hello"), do: bytes == "received: " <> input

  defp pty_matches?(bytes, "h\n", "canonical"),
    do: bytes == "READY\r\nWINDOW 68\r\nFINAL 680a\r\n"

  defp pty_matches?(bytes, input, "echo"),
    do: bytes == "input> received: " <> String.replace(input, "\n", "\r\n")

  defp pty_matches?(bytes, _, "ls"),
    do: Regex.match?(~r/\Aalpha[ \t]+bravo[ \t]+charlie\r\n\z/, bytes)

  defp pty_matches?(bytes, input, "hello") do
    echo = String.replace(input, "\n", "\r\n")
    bytes in ["input> " <> echo <> "received: " <> echo, echo <> "input> received: " <> echo]
  end

  defp receipt_path(definition, index, mode),
    do: Path.join(definition.directory, "pair-#{index}-#{mode}.jsonl")

  defp hash(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  defp write_new(file, bytes) do
    {:ok, fd} = :file.open(String.to_charlist(file), [:write, :binary, :exclusive, :raw])

    try do
      :ok = :file.write(fd, bytes)
      :ok = :file.sync(fd)
    after
      :ok = :file.close(fd)
    end

    :ok = File.chmod(file, 0o444)
  end
end
