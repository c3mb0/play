# PTY Playground

A small Unix process laboratory: terminal attachment topology is an explicit
experimental variable. Rust touches the machine; Erlang owns session lifecycle.

**First behavioral witness: observed PASS on macOS 26.6.1 arm64.**
The same hello-world program received `hello\n` through a pipe and a PTY. Both
replied `received: hello` and exited 0; only the PTY run enabled `input> `.
Original echo/CRLF bytes remain in the receipts. This is one intentionally
constructed pair, not a claim about unmodified applications.
[Results](experiments/witness_001/RESULT.md) ·
[Raw comparison](receipts/witness-20260910T203307Z/comparison.json).

The earlier Phase D receipt checkpoint passed:
Standalone session receipts now include binary fingerprints, helper/runtime
versions and a language-neutral environment hash. A real BEAM SIGKILL left a
partial journal that a fresh BEAM recovered byte-for-byte as incomplete/unknown.
All 14 receipt checks and the nine-session ownership regression passed. See
[receipt semantics and recovery](RECEIPTS.md).

The preceding Phase C ownership checkpoint also passed:
Nine OTP sessions covered topology, binary input, helper murder under pipes and
PTY, worker kill, timeout, and successful execution after faults in the same
BEAM. All reported processes in the fault cells were absent within three seconds.
The SIGHUP-ignoring lifetime probe makes cleanup independent of terminal hangup.
No Elixir, NIF, UI or terminal state matrix exists yet.

The earlier Phase A/B gate reproduced the real macOS Terminal reference on the
terminal dimensions declared before measurement:

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
* [Ownership gate plan](experiments/ownership_001/PLAN.md)
* [Passing ownership receipt](receipts/ownership-20260910T195848Z/manifest.json)
* [Framing evidence](receipts/protocol-20260910T195847Z/manifest.json)
* [Preserved failed first ownership run](receipts/ownership-20260910T195717Z/manifest.json)
* [Receipt checkpoint](experiments/receipt_001/RESULT.md)
* [Phase D evidence](receipts/receipt-20260910T202559Z/manifest.json)
* [First behavioral witness](experiments/witness_001/RESULT.md)

The first ownership run failed because Rust buffered non-newline protocol
events. Direct descriptor writes fixed the transport; a new, separately recorded
run passed. The failed binary-input journal is incomplete because the test BEAM
halted on the assertion; it is preserved, never synthesized into a complete run.

## OTP ownership

```text
pty_lab_sup
├── receipt_writer (independent worker monitor and durable journal owner)
└── session_sup
    └── session_worker (temporary, never replayed)
        └── external Port: Rust relay
            └── Rust guardian
                └── subject
```

The extra Rust process closes the macOS SIGKILL cleanup gap: the guardian owns
the subject and observes EOF when its relay dies. OTP deadlines send termination;
worker death closes the Port. The guardian kills/reaps the direct child. Killing
the guardian itself and descendant containment remain outside the guarantee.

Session journals are synchronously appended, sealed on completion/failure, and
monitored independently of workers. Original wire events, input/output hex,
command ordering, exit signals and timeout/failure outcomes remain inspectable.
The [protocol contract](protocol/README.md) explains bounds and error semantics.

Requires OTP 27+ for native JSON (tested with OTP 29.0.6), and rebar3 (3.27.0).
On this laptop add `/opt/homebrew/bin` alongside the Rust toolchain to PATH:

```sh
make otp-check       # compile, EUnit, cross-reference analysis
make protocol-check # real fragmented/coalesced/rejected frames; new evidence
make ownership-check # nine bounded sessions; new evidence, no retries
make receipt-check   # standalone metadata, BEAM kill, lossless recovery
make witness-check   # hello-world prompt flip, one matched pair
```

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

## Legacy Phase B CLI

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

This legacy CLI remains for gate_001 regression and has no crash-containment
promise. OTP uses `pty_helper --port` and the framed protocol instead. Only that
new path has the tested guardian ownership chain. Descendant cleanup remains
deferred in both paths.

The post-fork hook uses only session/terminal syscalls and immediate errno
capture, following Rust's [pre_exec safety requirements](https://doc.rust-lang.org/std/os/unix/process/trait.CommandExt.html#tymethod.pre_exec).
Only macOS has been runtime-tested; terminal constants and configurations are
platform-specific. Go vet/staticcheck are inapplicable to this Rust/Python tree;
Clippy is the Rust static-analysis gate.
