# gate_001: manufacture the gate

Scope: Phase A and B of the supplied PTY Playground plan. Start with a Rust
topology probe, freeze pipe and macOS Terminal references, then implement a
one-child Rust helper. Erlang, the framed Port protocol, behavioral witnesses,
and the state matrix remain deferred.

Prediction, before measurements:

* Pipes: all three isatty results false; terminal settings unavailable.
* PTY slave on stdio without a controlling terminal: all three isatty results
  true; termios and dimensions available; /dev/tty unavailable in an isolated
  session. Foreground-pgrp behavior is measured, not assumed portable.
* PTY with controlling terminal: additionally /dev/tty accessible and the
  foreground process group equals the subject process group.

First checkpoint passes only when the helper matches the macOS Terminal
reference on all three isatty results, all termios fields/control characters/
speeds, dimensions, controlling-terminal accessibility, and foreground-pgrp
equality to the subject pgrp. PIDs, PPIDs, absolute SID/pgrp numbers and session
leadership are observations, excluded from equality. The helper deliberately
creates a session; the reference is an ordinary shell job.

The identical subject binary, argv, explicit environment, cwd and empty input
are recorded. Probe does not read input. Pipe EOF versus live terminal input is
therefore outside this checkpoint. Launch scheduling is uncontrolled; each cell
has a 10-second external deadline, zero retries, and retained failure evidence.

Terminal capture uses a create-new side-channel file because redirecting probe
stdout would destroy the property being measured. Original stdout bytes are
also retained where the controller owns the stream. Terminal screen output is
not claimed to be a byte transcript.

Freeze reference evidence and commit it before introducing the helper. Preserve
raw observations and errors; compare selected fields in a separate interpretation.
Do not call this the OTP acceptance test: helper murder/worker death, durable
session receipts and lifecycle recovery have not yet been implemented.
