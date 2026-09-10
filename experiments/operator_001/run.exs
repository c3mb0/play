defmodule OperatorExhibit do
  def run do
    root = System.fetch_env!("PTY_LAB_ROOT")
    directory = System.fetch_env!("PTY_LAB_RUN")
    Process.put(:root, root)
    Process.put(:directory, directory)
    {:ok, _} = Application.ensure_all_started(:pty_lab)

    cases = [
      input_wait(),
      blocked_output(),
      stopped(),
      held_output(),
      caller_death(),
      worker_death()
    ]

    write_new(Path.join(directory, "report.json"), %{
      kind: "interpretation",
      cases: cases,
      retries: 0,
      scope: "cooperative fixtures plus external OS observations; no generic wait classifier"
    })

    IO.puts("operator exhibits: #{length(cases)} passed")
  end

  defp input_wait do
    s = start("input_wait", "cat")
    {:error, :event_timeout} = :pty_session.await_event(s.h, "stdout", 100)
    before = snapshot(s.spawn["pid"])
    :ok = action(s, "write", "hello\n", fn -> :pty_session.send_input(s.h, "hello\n") end)
    {:ok, _} = :pty_session.await_event(s.h, "input_written", 1000)
    :ok = action(s, "close_stdin", "pipe stdin", fn -> :pty_session.close_stdin(s.h) end)
    r = result(s)
    ensure(r.child_exit == %{"code" => 0, "signal" => :null}, "cat exit")
    ensure(stream(s, "stdout") == "hello\n", "cat application output")

    {:error, :session_closed} =
      action(s, "write", "late", fn -> :pty_session.send_input(s.h, "late") end)

    absent(s.pids)

    finish(s, %{
      diagnosis: "unknown from silence alone",
      alternatives: ["input wait", "other blocking", "not scheduled"],
      external_before: before,
      effect: "hello output and zero exit; late write rejected"
    })
  end

  defp blocked_output do
    s = start("blocked_output", "flood")
    ready(s)
    guardian = s.spawn["guardian_pid"]
    signal(s, guardian, "STOP")

    observation =
      try do
        state = snapshot(guardian)

        ensure(
          String.contains?(Enum.at(String.split(state.output), 2, ""), "T"),
          "guardian stopped"
        )

        ensure(
          not File.exists?(Path.join(s.dir, "write_started")),
          "guardian stopped before write intent"
        )

        wait(fn -> File.exists?(Path.join(s.dir, "write_started")) end, 1000)
        pause(100)

        ensure(
          not File.exists?(Path.join(s.dir, "write_finished")),
          "write not completed while undrained"
        )

        %{
          guardian: state,
          subject: snapshot(s.spawn["pid"]),
          write_started: true,
          write_finished: false
        }
      after
        signal(s, guardian, "CONT")
      end

    r = result(s)
    ensure(r.child_exit == %{"code" => 0, "signal" => :null}, "flood exit")

    ensure(
      stream(s, "stdout") == "READY\n" <> :binary.copy("X", 262_144),
      "complete flood output"
    )

    ensure(File.exists?(Path.join(s.dir, "write_finished")), "write finished after resume")
    absent(s.pids)

    finish(s, %{
      diagnosis: "unknown from session silence alone",
      interpretation:
        "controlled stop/resume and cooperative markers support output backpressure",
      alternatives: ["writer not scheduled", "other blocking after intent marker"],
      external_before: observation,
      effect: "256 KiB drained and write finished after guardian resume"
    })
  end

  defp stopped do
    s = start("stopped", "hold")
    ready(s)
    child = s.spawn["pid"]
    signal(s, child, "STOP")

    observation =
      try do
        state = snapshot(child)

        ensure(
          String.contains?(Enum.at(String.split(state.output), 2, ""), "T"),
          "subject stopped"
        )

        state
      after
        signal(s, child, "CONT")
      end

    :ok = action(s, "terminate", "direct child", fn -> :pty_session.terminate(s.h) end)
    r = result(s)
    ensure(r.child_exit == %{"code" => :null, "signal" => 9}, "observed termination signal")
    absent(s.pids)

    finish(s, %{
      diagnosis: "stopped according to external OS state",
      external_before: observation,
      effect: "API accepted termination; receipt observed signal 9; independent absence passed"
    })
  end

  defp held_output do
    s = start("held_output", "held_output")
    ready(s)
    holder = holder(s)

    try do
      :ok = action(s, "write", "x", fn -> :pty_session.send_input(s.h, "x") end)
      wait(fn -> not alive?(s.spawn["pid"]) end, 1000)
      ensure(alive?(holder), "descriptor holder alive")
      {:error, :event_timeout} = :pty_session.await_event(s.h, "child_exit", 100)

      observation = %{
        parent: snapshot(s.spawn["pid"]),
        holder: snapshot(holder),
        child_exit_event: "not received"
      }

      signal(s, holder, "TERM")
      r = result(s)

      ensure(
        r.child_exit == %{"code" => 0, "signal" => :null},
        "parent zero exit after holder release"
      )

      absent(s.pids ++ [holder])

      finish(s, %{
        diagnosis: "unknown from transcript alone",
        external_before: observation,
        interpretation:
          "parent absent; cooperative descendant retained output descriptors; child_exit arrived after descriptor release"
      })
    after
      cleanup_holder(s, holder)
    end
  end

  defp caller_death do
    parent = self()
    root = Process.get(:root)
    directory = Process.get(:directory)

    {caller, ref} =
      spawn_monitor(fn ->
        Process.put(:root, root)
        Process.put(:directory, directory)
        s = start("caller_death", "hold", 1200)
        ready(s)
        send(parent, {:caller_ready, self(), s})
        :pty_session.await_result(s.h, 3000)
      end)

    s =
      receive do
        {:caller_ready, ^caller, s} -> s
      after
        2000 -> raise "caller setup timeout"
      end

    action(s, "kill_caller", inspect(caller), fn -> Process.exit(caller, :kill) end)

    receive do
      {:DOWN, ^ref, :process, ^caller, :killed} -> :ok
    after
      1000 -> raise "caller did not die"
    end

    pause(100)
    observation = %{worker_alive: Process.alive?(s.h.worker), child_alive: alive?(s.spawn["pid"])}
    ensure(observation.worker_alive and observation.child_alive, "caller is not Port owner")
    receipt(s)
    absent(s.pids)
    terminal = List.last(events(s))
    ensure(terminal["data"]["outcome"] == "timeout", "OTP deadline after caller death")

    finish(s, %{
      diagnosis: "caller death did not cancel session",
      external_before: observation,
      effect: "existing OTP deadline reclaimed direct process chain; receipt remained available"
    })
  end

  defp worker_death do
    s = start("worker_death_descendant", "descendant")
    ready(s)
    holder = holder(s)

    try do
      action(s, "kill_worker", inspect(s.h.worker), fn -> Process.exit(s.h.worker, :kill) end)
      receipt(s)
      absent(s.pids)
      ensure(alive?(holder), "descendant survives direct-child cleanup")
      observation = snapshot(holder)
      signal(s, holder, "TERM")
      absent([holder])

      finish(s, %{
        diagnosis: "Port owner died; direct chain reclaimed; descendant survived",
        external_before: observation,
        effect: "independent fixture cleanup terminated descendant; not a containment guarantee"
      })
    after
      cleanup_holder(s, holder)
    end
  end

  defp start(name, mode, deadline \\ 5000) do
    root = Process.get(:root)
    directory = Process.get(:directory)
    dir = Path.join(directory, name)
    :ok = File.mkdir(dir)

    id = %{
      "run" => Path.basename(directory),
      "experiment" => "operator_001",
      "cell" => name,
      "session" => name
    }

    exe = if mode == "cat", do: "/bin/cat", else: Path.join(root, "target/debug/operator_subject")
    args = if mode == "cat", do: [], else: [mode, dir]

    {:ok, h} =
      :pty_session.start_session(%{
        identity: id,
        helper: String.to_charlist(Path.join(root, "target/debug/pty_helper")),
        receipt: String.to_charlist(Path.join(dir, "session.jsonl")),
        deadline_ms: deadline,
        spec: %{
          "executable" => exe,
          "argv" => args,
          "cwd" => root,
          "attachment" => "pipe",
          "environment" => %{"PATH" => "/usr/bin:/bin", "LANG" => "C", "TERM" => "dumb"}
        }
      })

    {:ok, %{"data" => spawn}} = :pty_session.await_event(h, "spawned", 1000)

    s = %{
      name: name,
      dir: dir,
      h: h,
      spawn: spawn,
      pids: Enum.map(["helper_pid", "guardian_pid", "pid"], &spawn[&1])
    }

    for role <- ["helper_pid", "guardian_pid", "pid"] do
      log("custody", %{
        case: name,
        role: role,
        pid: spawn[role],
        executable: if(role == "pid", do: exe, else: Path.join(root, "target/debug/pty_helper"))
      })
    end

    s
  end

  defp ready(s) do
    {:ok, %{"data" => %{"hex" => hex}}} = :pty_session.await_event(s.h, "stdout", 1000)
    ensure(Base.decode16!(hex, case: :mixed) == "READY\n", "fixture ready")
  end

  defp holder(s) do
    pid = s.dir |> Path.join("holder.pid") |> File.read!() |> String.trim() |> String.to_integer()

    log("custody", %{
      case: s.name,
      role: "holder",
      pid: pid,
      executable: Path.join(Process.get(:root), "target/debug/operator_subject")
    })

    pid
  end

  defp result(s) do
    {:ok, r} = :pty_session.await_result(s.h, 3000)
    receipt(s)

    log("interventions", %{
      phase: "session_effect",
      identity: s.h.identity,
      receipt: List.to_string(s.h.receipt),
      outcome: r.outcome,
      child_exit: r.child_exit
    })

    r
  end

  defp receipt(s) do
    file = List.to_string(s.h.receipt)
    wait(fn -> File.exists?(file <> ".sha256") end, 3000)
    a = :receipt_recovery.analyze(File.read!(file), {:present, File.read!(file <> ".sha256")})

    ensure(
      a.integrity == "verified" and a.classification == "complete",
      "complete verified receipt"
    )

    a
  end

  defp events(s),
    do:
      s.h.receipt
      |> List.to_string()
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(&:json.decode/1)

  defp stream(s, name),
    do:
      for(
        %{"event" => "helper_event", "data" => %{"event" => ^name, "data" => %{"hex" => hex}}} <-
          events(s),
        into: "",
        do: Base.decode16!(hex, case: :mixed)
      )

  defp finish(s, details) do
    report =
      Map.merge(details, %{
        case: s.name,
        acceptance: "pass",
        identity: s.h.identity,
        receipt: List.to_string(s.h.receipt),
        pids: s.pids
      })

    write_new(Path.join(s.dir, "interpretation.json"), report)
    report
  end

  defp action(s, verb, target, fun) do
    id = :erlang.unique_integer([:positive, :monotonic])

    log("interventions", %{
      phase: "request",
      action_id: id,
      identity: s.h.identity,
      receipt: List.to_string(s.h.receipt),
      operation: verb,
      target: target,
      deadline_ms: 3000,
      preconditions: %{worker_alive: Process.alive?(s.h.worker)},
      meaning: "observed precondition, not atomic guard"
    })

    result = fun.()

    log("interventions", %{
      phase: "response",
      action_id: id,
      response: inspect(result),
      meaning: "return value, not proof of effect"
    })

    result
  end

  defp signal(s, pid, name) do
    {_, 0} =
      action(s, "external_signal_#{name}", pid, fn ->
        os("/bin/kill", ["-#{name}", Integer.to_string(pid)])
      end)

    :ok
  end

  defp cleanup_holder(s, pid), do: if(alive?(pid), do: signal(s, pid, "TERM"), else: :ok)

  defp snapshot(pid) do
    {out, code} = os("/bin/ps", ["-p", Integer.to_string(pid), "-o", "pid=,ppid=,stat=,comm="])
    %{pid: pid, exit_code: code, output: out, unix_ns: System.system_time(:nanosecond)}
  end

  defp alive?(pid), do: snapshot(pid).exit_code == 0

  defp absent(pids) do
    wait(fn -> Enum.all?(pids, &(not alive?(&1))) end, 3000)
    log("interventions", %{phase: "absence_observed", pids: pids})
  end

  defp os(exe, args) do
    port =
      Port.open({:spawn_executable, String.to_charlist(exe)}, [
        :binary,
        :exit_status,
        :use_stdio,
        :stderr_to_stdout,
        :hide,
        {:args, Enum.map(args, &String.to_charlist/1)}
      ])

    collect(port, "", System.monotonic_time(:millisecond) + 1000)
  end

  defp collect(port, bytes, deadline) do
    remaining = max(0, deadline - System.monotonic_time(:millisecond))

    receive do
      {^port, {:data, more}} ->
        ensure(byte_size(bytes) + byte_size(more) < 16384, "OS output bound")
        collect(port, bytes <> more, deadline)

      {^port, {:exit_status, code}} ->
        {bytes, code}
    after
      remaining ->
        Port.close(port)
        raise "OS utility timeout"
    end
  end

  defp wait(fun, ms), do: wait_until(fun, System.monotonic_time(:millisecond) + ms)

  defp wait_until(fun, deadline) do
    if fun.() do
      :ok
    else
      ensure(System.monotonic_time(:millisecond) < deadline, "bounded observation timeout")
      pause(10)
      wait_until(fun, deadline)
    end
  end

  defp pause(ms), do: receive(do: (:never -> :ok), after: (ms -> :ok))
  defp ensure(true, _), do: :ok
  defp ensure(false, message), do: raise(message)

  defp write_new(file, map) do
    {:ok, fd} = :file.open(String.to_charlist(file), [:write, :exclusive, :binary, :raw])

    try do
      :ok = :file.write(fd, [:json.encode(map), "\n"])
      :ok = :file.sync(fd)
    after
      :file.close(fd)
    end
  end

  defp log(name, map) do
    map =
      Map.merge(map, %{
        unix_ns: System.system_time(:nanosecond),
        sequence: :erlang.unique_integer([:positive, :monotonic])
      })

    {:ok, fd} =
      :file.open(String.to_charlist(Path.join(Process.get(:directory), name <> ".jsonl")), [
        :append,
        :binary,
        :raw
      ])

    try do
      :ok = :file.write(fd, [:json.encode(map), "\n"])
      :ok = :file.sync(fd)
    after
      :file.close(fd)
    end
  end
end

OperatorExhibit.run()
