# Checkpoint handoff

## Current: initial-width axis, 2026-09-11 local / 2026-09-10 UTC

Three PTY/PTY pairs of installed /bin/ls passed: initial columns 80 then 8, same
fixture/argv/environment/cwd/empty input. Wide output alpha\tbravo\tcharlie\r\n;
narrow alpha\r\nbravo\r\ncharlie\r\n. Native readback verifies only cols changed;
rows, pixels and all termios remain fixed. No emulator wrapping or resize signal.

Plan 7e9b6a2; runtime source 6fd4052; receipts width-20260910T212259Z. One run,
zero retries, six verified sealed receipts, eighteen reported PIDs absent, 1.641 s.
Fixture and subject hashes unchanged; ordering/max concurrency two verified.
Six Elixir tests, formatting/compilation, Clippy/Python syntax passed. Regressions
ls-20260910T212301Z, echo-20260910T212302Z, canonical-20260910T212304Z and
elixir-20260910T212307Z all passed. No Rust/Erlang/dependency changes.
See experiments/width_001/RESULT.md, make width-check and run_width_pairs/1.

The user explicitly selected MIT during this checkpoint. Root LICENSE and Rust,
Erlang and Elixir package metadata now declare MIT; copyright uses the configured
Git identity c3mb0 and contributors, year 2026. Third-party dependencies and quoted
reference material retain their licenses. Historical receipts were not edited.

Next experimental candidate: live resize and observed SIGWINCH, with a new
predeclared bounded witness. Initial width does not establish signal behavior.
No such experiment has been started; no factorial matrix expansion is implied.
Prior setup-readback, guardian, descendant and platform limits persist.

## Historical: ICANON delivery axis, 2026-09-11 local / 2026-09-10 UTC

Three canonical-on/off PTY pairs passed with echo off in both. New byte_witness
uses poll plus one-byte libc::read, with a fixed 400 ms early window and bounded
final reads. Same h-newline input: send h after READY; wait for WINDOW result;
then send newline in both conditions. Canonical reported WINDOW NONE, noncanonical
WINDOW 68; both reported FINAL 680a and exited zero. Native readback confirms
only ICANON (256) changed; ECHO off, VMIN=1 and VTIME=0 remained fixed.

Plan f1db193; runtime source 14c45ea; receipts canonical-20260910T211835Z. One run,
zero retries, six sealed verified receipts, eighteen reported PIDs absent, 3.380 s.
Journal phase ordering and max concurrency two verified. Controller-side ack-to-
WINDOW intervals 396.565–405.002 ms; not exact kernel/probe timing. No normalization.

Five Elixir tests, formatting/compilation, Clippy/Python syntax passed. Regressions
echo-20260910T211839Z, elixir-20260910T211840Z, ls-20260910T211845Z all passed.
Erlang unchanged; helper only adds native mask/cc identifiers to setup readback.
Cargo dependency versions unchanged. See experiments/canonical_001/RESULT.md and
make canonical-check; public run_canonical_pairs/1 documented in the Elixir README.

Next candidate: initial terminal width using unmodified ls. Predeclare widths,
fixture and layout predicates first; do not silently add resize/SIGWINCH or a
factorial matrix. No width experiment has been started. Existing setup-readback,
guardian, descendant and platform limits persist.

## Historical: ECHO axis, 2026-09-11 local / 2026-09-10 UTC

Three PTY-slave pairs through run_echo_pairs/1 passed. Same hello_witness and
hello\n input; only ECHO (macOS 0x8) changed. Rust now reads slave termios/dimensions
before child spawn and includes terminal_observation in spawned. Applied settings
matched requested settings exactly; lflag 536872395 versus 536872387. Echo off
preserved the application prompt/reply and removed terminal input echo.

Plan 79e4855; runtime source caaa307; evidence echo-20260910T211145Z. One run,
zero retries, six verified sealed receipts, all eighteen reported PIDs absent,
2.012 seconds. Echo-on pairs 1/2 emitted echo before prompt, pair 3 prompt before
echo; both orders were predeclared and preserved. No schedule normalization.

Four Elixir tests, seven EUnit tests, xref, Clippy, formatting/compilation and
Python syntax passed. Updated-helper runtime regressions: elixir-20260910T211147Z,
ls-20260910T211152Z, ownership-20260910T211154Z, receipt-20260910T211156Z all passed.
See experiments/echo_001/RESULT.md; reproduce with make echo-check.

Next bounded candidate: ICANON on/off with a byte-reading witness, fixed echo off
and explicit input timing. The current read_line hello witness would conceal the
kernel delivery distinction behind application line buffering. Predeclare the
next axis first; no canonical/raw implementation or experiment has been started.
Setup readback is not continuous monitoring. Prior guardian/descendant/platform
limits persist. No factorial matrix, UI or generalized DSL has been added.

## Historical: unmodified ls witness, 2026-09-11 local / 2026-09-10 UTC

Completed three matched /bin/ls pipe/PTY pairs through shared Elixir scheduling.
Prediction was predeclared in 3e96d8f; initial runner source 88c5d43. First attempt
ls-20260910T210550Z preserved as failed: uppercase/lowercase digest-text assertion
in Python after the three Elixir layout comparisons passed. No bounded cleanup
or post-run fixture evidence is claimed for that interrupted checker.

Committed the explicit correction and second-run declaration in 149172b, then
ls-20260910T210628Z passed in 1.503 seconds: six sealed verified receipts, fixture
and subject hashes unchanged, maximum concurrency two, all eighteen reported PIDs
absent. Pipe bytes alpha\nbravo\ncharlie\n; PTY bytes
alpha\tbravo\tcharlie\r\n in all three pairs. Two explicit attempts, no automatic
retries. Original failed evidence unchanged, predicates unchanged.

Three Elixir tests, formatting/compilation, Clippy/Python checks passed. Existing
Elixir normal/mismatch/execution-failure runtime regression passed in
elixir-20260910T210629Z. No Rust or Erlang mechanism changes. See
experiments/ls_001/RESULT.md and `make ls-check`.

Next candidate: predeclare echo on/off for the existing hello-world witness.
No echo-axis implementation or new experiment has been started. Do not expand
the matrix automatically. Existing guardian/descendant/platform limits persist.

## Historical: plumbing isolation and thin Elixir plane, 2026-09-10

Completed the approved bounded plumbing pass before adding Elixir. Full four-part
session identity, checked Port sends, isolated receipt errors, writer-death
termination without replay, and the public pty_session API are implemented.
Isolation's six scenarios passed; the existing witness, nine ownership checks
and fourteen receipt checks passed again. Plumbing/evidence commit c3e2e08 was
published before the Elixir implementation.

Elixir source b9b3c8f runs ordinary function/map experiment definitions over that
API, with bounded concurrency, pipe-before-PTY order, preserved anomalies and
separate checksummed interpretation reports. Runtime evidence:
`receipts/elixir-20260910T205341Z`. Nine pairs / eighteen sessions: three normal
passes; one deliberate mismatch and one execution failure correctly classified
in separate three-pair experiments; subsequent pairs passed. All journals sealed
and verified, all fifty reported PIDs absent. One run, zero retries, 4.674 seconds.
Formatting, compilation with warnings as errors, Clippy/Python syntax and the
fixed-seed Elixir classification test passed. See experiments/elixir_001/RESULT.md
and elixir/pty_lab_ex/README.md for reproduction and limits.

Only the constructed witness and macOS have been runtime-tested. Guardian death,
descendant containment and the terminal-variable matrix remain deferred. The
next candidate is a predeclared matched pair for an unmodified application;
there is no authorization inferred here to expand into a framework or matrix.

Origin remains git@github.com:c3mb0/play.git. SSH authentication failed this turn;
publishing used a per-command HTTPS credential helper through the already
signed-in gh account. No credentials or global Git/shell configuration changed.
User authorization to push persists. Checkout: /Users/cem/play/pty-lab.

## Historical: constructed behavioral witness, 2026-09-10

Completed the user's hello-world ping-pong witness. A tiny Rust program enables
`input> ` if stdin is terminal-attached, reads one line, and replies `received: `
plus that line. Erlang runs one matched pipe/PTY-slave pair using identical task
definition, fresh-session setup, frozen terminal settings and input timing policy.

Observed PASS: `receipts/witness-20260910T203307Z`. Pipe raw output was
`received: hello\n`; PTY raw output was `input> hello\r\nreceived: hello\r\n`.
Actual input was `hello\n` in both; child exits were 0 without signals. All six
reported OS PIDs were gone after the run. Journals were complete/verified v2.

Plan `de83650`; runtime source `c270bb8`. One pair, zero retries, about 1.44 s total.
Input-request delays were 101.414/101.791 ms for a shared 100 ms policy; exact
scheduling is not claimed equal. No EOF command, prompt-dependent input policy,
terminal mode changes, source normalization or controlling terminal was used.
Build, Clippy, syntax, EUnit and xref passed. Helper/writer/recovery code unchanged.

Origin remains `git@github.com:c3mb0/play.git`; user authorization to push persists.
Checkout remains `/Users/cem/play/pty-lab`. Results and bounded reproduction are
in experiments/witness_001 and `make witness-check`.

Next candidate: select one unmodified application's documented terminal-sensitive
behavior and predeclare another matched pair. This checkpoint validates a witness
we intentionally constructed; it says nothing yet about arbitrary programs or
repeatability. Do not expand the terminal-variable matrix automatically.

## Historical Phase D handoff

Completed standalone v2 receipt headers and explicit non-destructive recovery.
Helper 0.3.0 adds `--metadata`; machine/session mechanism is otherwise unchanged.
Headers bind run ID, requested task/topology, executable/helper pre-spawn SHA-256,
helper-reported version, canonical environment hash, platform and Erlang code
identities. Full observations remain ordered journal events.

Observed PASS: `receipts/receipt-20260910T202559Z`, 14 checks in about 4.94 seconds.
Actual BEAM SIGKILL was injected only after the lifetime subject reported ready
and the journal synced. All reported OS processes disappeared within 3 seconds.
Fresh-VM recovery produced an exact raw snapshot, classified incomplete/unknown,
without changing source bytes or inventing an exit. Detached normal receipt
verified independently; synthetic corruption cases were quarantined; destination
reuse rejected. No failed runtime attempt in this checkpoint.

Source committed before execution: `b4883b8`. Existing nine-session ownership
gate passed again in `receipts/ownership-20260910T202628Z`. Build, Clippy, Rust
tests, seven EUnit tests, xref, syntax and custody checks passed.

The user supplied `git@github.com:c3mb0/play.git` and explicitly authorized push.
It was empty on inspection and is configured as origin. The project repository
remains `/Users/cem/play/pty-lab`; no relocation of the checkout was needed.

Next bounded step: Phase E/F first behavioral witness, holding task content and
launch definition constant across pipe and PTY. Keep receipt observation separate
from comparison; predeclare the expected behavior and failure conditions. Do not
expand the terminal-variable matrix yet.

Recovery snapshots do not resume runs or restore writer state. Guardian SIGKILL,
descendants, exec-time attestation, power-loss durability and Linux runtime remain
outside tested scope. See RECEIPTS.md for exact completeness/integrity semantics.

## Historical Phase C handoff

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
