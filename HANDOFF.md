# Checkpoint handoff

## Current: Phase C, 2026-09-10

Implemented OTP supervision/session workers, external Port framing v1, a Rust
relay/guardian ownership chain, byte input and pipe EOF, bounded OTP deadlines,
and an independent durable journal writer. Helper version is 0.2.0. Phase A/B
reference files remain unchanged and the probe binary hash still matches them.

Observed PASS: `receipts/ownership-20260910T195848Z`, nine sessions, in one BEAM.
Helper SIGKILL under pipes and ctty, worker kill, and timeout all reclaimed their
reported relay/guardian/subject PIDs within three seconds. The lifetime probe
ignores SIGHUP. A fresh post-failure session completed; supervisors survived.
Five actual framing cases passed in `receipts/protocol-20260910T195847Z`.

Preserved failure: `receipts/ownership-20260910T195717Z`. Buffered Rust stdout
delayed framed events until timeout. Corrected with raw descriptor writes before
the new passing run. Its unfinished binary-input journal is evidence of the test
BEAM's early halt, not a completed session receipt. No automatic retries exist.

Runtime source: `675f107`; initial implementation: `e2833a9`. Further handoff/test
changes do not alter the passing Rust/OTP runtime. EUnit validates decoder
version/identity/sequence boundaries; Clippy and compiler warnings are errors.
Xref exempts only five named externally invoked API/supervisor entrypoints.

Installed via Homebrew: Erlang 29.0.6 and rebar3 3.27.0, plus unixodbc and wxwidgets.
Homebrew also upgraded their dependencies ca-certificates, openssl@3, libtool,
jpeg-turbo, libtiff and pcre2. No shell configuration was edited.

Scope limits: guardian SIGKILL, descendant trees, full-BEAM/journal-writer crash
recovery, Linux runtime, PTY EOF semantics and the terminal-variable matrix are
not tested. Normal covered worker/helper failures yield sealed journals; abrupt
BEAM death can leave partial ones. Run summaries bind source/binary hashes and
platform; standalone session journals currently rely on that enclosing custody.

Next bounded work: strengthen/review the Phase D receipt contract (self-contained
metadata and partial-journal recovery) before the Phase E/F behavioral witness.
Do not add terminal state axes yet. Current evidence is ready for user review.

## Historical Phase A/B handoff

The following records the previous checkpoint; its "next" and "known limits"
paragraphs describe that earlier state, not the current Port path.

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
