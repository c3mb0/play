# PTY Playground

A small Unix process laboratory: terminal attachment topology is an explicit
experimental variable. Rust touches the machine; Erlang will own lifecycle.

**Phase A/B laptop checkpoint: observed PASS on macOS 26.6.1 arm64.**
The Rust helper reproduced the real macOS Terminal reference on the terminal
dimensions we declared before measuring. This is the first gate, not the full
OTP acceptance test. No Erlang, Elixir, NIF, UI or behavioral witness exists yet.

| Measured property | Pipes | PTY slave only | PTY + controlling terminal | Real Terminal |
| --- | --- | --- | --- | --- |
| isatty stdin/stdout/stderr | all false | all true | all true | all true |
| terminal settings | ENOTTY | match reference | match reference | frozen reference |
| `/dev/tty` accessible | no | no | yes | yes |
| foreground pgrp | ENOTTY | ENOTTY | subject pgrp | subject pgrp |

Matched fields include all termios flag words, control characters, input/output
speeds, rows/columns and pixel dimensions. Numeric process identities, ancestry
and session leadership differ and remain visible in the original observations.
The complete probe can distinguish the processes; its declared terminal
projection cannot distinguish the controlling-PTY cell from the reference.

## Evidence and source custody

* [Predeclared checkpoint](experiments/gate_001/PLAN.md)
* [Reference observations and interpretation](experiments/gate_001/REFERENCE.md)
* [Frozen pre-harness reference](receipts/reference-20260910T194106Z/manifest.json)
* [Gate receipt](receipts/gate-20260910T194539Z/manifest.json)
* [Explicit comparison](receipts/gate-20260910T194539Z/comparison.json)
* [Handoff and limits](HANDOFF.md)

The probe, argv, explicit environment, cwd and empty input are identical across
the topology cells. A side-channel snapshot preserves stdio attachment. Raw pipe
and PTY bytes are retained separately, including terminal newline processing.
Terminal's screen is not claimed as a captured byte stream. The probe does not
read input; this experiment establishes nothing about EOF or interactive timing.

Reference source was committed before capture (`f30c10d`), reference evidence
before helper implementation (`fe204cd`), and helper/check source before execution
(`da17020`). Per-run SHA-256 manifests, read-only files and Git preserve evidence.
These are local tamper-evident artifacts, not WORM storage. Failures are retained;
there are no automatic experimental retries.

## Build and check

Requires Rust 1.95.0 with rustfmt/clippy, Python 3, and macOS for reference capture.
Cargo.lock is committed. Cargo must find rustc on PATH. On this laptop:

```sh
export PATH="$HOME/.rustup/toolchains/1.95.0-aarch64-apple-darwin/bin:$PATH"
make build
make lint
make check
```

`make check` creates a new receipt and verifies the frozen probe binary hash
before executing. A different compiler, checkout location or build profile can
change that hash; investigate such a mismatch instead of accepting it silently.
To deliberately capture a new reference with the current binary, run
`make reference`, then pass its new directory explicitly:

```sh
make check REFERENCE=receipts/reference-YYYYMMDDTHHMMSSZ
```

Reference capture opens a fresh macOS Terminal window and runs a foreground Bash
job with 24 x 80 cells; native pixel dimensions and termios are observed. It leaves
that window available for inspection. Each cell has a bounded wait. Terminal
launch failure/timeout is retained and needs inspection; this temporary capture
script does not provide OTP resource recovery.

The functional checks cover slave-only attachment, controlling-terminal
equivalence, exact ENOENT on exec failure, deadline termination and reaping of a
sleeping child, and child exit-code propagation. They compare observed behavior,
not implementation text. There are no Rust unit tests at this checkpoint.

## Mechanism boundary

```text
pty_helper CONFIG_JSON slave|ctty DEADLINE_MS -- EXECUTABLE [ARGS...]
```

The configuration contains `termios` and `dimensions` (see a receipt's
`terminal-config.json`). The helper inherits the caller's cwd and environment;
the experiment script supplies the fixed environment. Both PTY modes create a
fresh session, isolating inherited controlling-terminal membership. `ctty` also
attaches the slave as controlling terminal and sets the subject foreground group.

Stdout carries raw, merged PTY bytes, buffered up to 1 MiB; stderr carries local
JSON diagnostics. The helper owns one direct child, closes the parent's slave
copies, drains the master, and observes/reaps exit. It accepts a 1..60000 ms
I/O-loop deadline and allows at most one second for kill/reap cleanup. Exit 125
means helper failure; child exit details distinguish it from a subject exiting
125. No stdin forwarding or terminal state matrix is implemented.

This is **not** the future framed/versioned Port protocol. Full event identity,
per-chunk timing, signal observations, interactive writes, crash-safe ownership
and descendant cleanup remain deferred. Killing the helper can bypass its Rust
destructors; no helper-murder survival claim is made.

The post-fork hook uses only session/terminal syscalls and immediate errno
capture, following Rust's [pre_exec safety requirements](https://doc.rust-lang.org/std/os/unix/process/trait.CommandExt.html#tymethod.pre_exec).
Only macOS has been runtime-tested; terminal constants and configurations are
platform-specific. Go vet/staticcheck are inapplicable to this Rust/Python tree;
Clippy is the Rust static-analysis gate.
