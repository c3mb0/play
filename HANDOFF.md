# Checkpoint handoff

Completed locally, 2026-09-10: requested immediate laptop task, Phases A/B.
Repository: `/Users/cem/play/pty-lab`. No upstream remote configured.

Observation: gate receipt `gate-20260910T194539Z` passed all five cells. The real
Terminal reference and ctty helper observations match on the complete declared
terminal projection. Slave-only attachment independently exposes a TTY without
controlling-terminal access. The subject executable hash is identical in all
three probe conditions and the reference. Every spawned PID in the helper
checks was absent when the helper returned, including the deadline cell.

Toolchain used: rustc 1.95.0 (59807616e, 2026-04-14), Cargo 1.95.0,
aarch64-apple-darwin. Build, formatting and Clippy passed; the bounded functional
check passed once, with zero retries. Initial helper compile errors (Darwin FFI
mutability/type differences and an inferred Result type) and Clippy findings
were fixed before any helper experiment ran. No failed runtime cell was hidden.

The first toolchain lookup caused the installed rustup launcher to download
stable components. Builds used the already-installed explicit 1.95.0 toolchain;
no login shell or shell configuration was edited.

User acceptance is pending review of the concrete artifacts. Do not promote
this local checkpoint into full architecture acceptance.

Next, if continuing the supplied plan: Phase C, a small Erlang OTP owner using
an external Port and a framed/versioned protocol. Erlang and rebar3 were absent
from the inspected command path. Establish the worker/helper/child cleanup
contract before promising that killing a helper or worker reclaims subjects.
Then test helper death while BEAM survives; preserve terminal failure receipts.
Do not start the behavioral witness or matrix before that gate.

Known limits: one-shot local helper, no input forwarding, direct child only,
buffered output with no per-chunk timestamps, no full session receipt schema,
no recovery from helper SIGKILL, no descendant cleanup guarantee, and no Linux
runtime evidence. Python capture/check scripts are bounded checkpoint scaffolding,
not a replacement orchestration architecture. Normal Terminal reference ancestry
differs from helper-created session leadership by design and is not normalized.
