# ls_001 — observed layout flip

PASS on the installed macOS /bin/ls. Three matched pairs completed with six
verified sealed receipts and zero child exits. No arguments or input were sent.
All pairs used the same fixture, environment and existing terminal configuration.

| Attachment | Exact observed output (escaped) |
| --- | --- |
| Pipe stdout | `alpha\nbravo\ncharlie\n` |
| PTY output | `alpha\tbravo\tcharlie\r\n` |

Every pair produced these bytes. Horizontal column layout, beyond newline
conversion, satisfies the predeclared behavioral prediction. Pipe stderr was
empty. Raw PTY output remains merged; separate PTY stderr is not observable.

[Passing manifest](../../receipts/ls-20260910T210628Z/manifest.json) and
[comparison](../../receipts/ls-20260910T210628Z/pairs/report.json).
Runtime source: `149172bde14d3989e9fe27f1674ac8fb3db6af02`.
Elapsed 1.503 seconds under the 60-second watchdog. All 18 reported PIDs were
absent within the cleanup bound. Journal timestamps verify pipe completion before
PTY start per pair and maximum concurrency two. Fixture names, regular-file
status, modes, sizes and content hashes matched before/after, as did /bin/ls hash.

## Preserved harness failure

There were TWO explicit attempts, zero automatic retries. The
[first attempt](../../receipts/ls-20260910T210550Z/manifest.json), source 88c5d43,
remains failed. Its three Elixir comparisons passed, but the outer checker
compared uppercase and lowercase SHA-256 text as unequal. It stopped before
post-run fixture and bounded PID checks, so those checks are not claimed for it.

The correction compares decoded digest bytes. A committed plan addendum declared
the second run before execution. No output predicate, subject definition or
original receipt was changed. Source/evidence custody distinguishes the failed
harness run from the subsequent passing validation.

## Validation and limits

Formatting, compile with warnings as errors, Clippy, Python syntax and all three
fixed-seed Elixir tests passed. The new tests reject CRLF-only layout changes and
changed argv even when output matches. The existing hello-world acceptance suite
also passed after sharing the runner: three normal pairs, correctly classified
mismatch and execution-failure cases, and successful later pairs. Its eighteen
receipts and cleanup evidence are in
[the regression manifest](../../receipts/elixir-20260910T210629Z/manifest.json).

Reproduce with `make ls-check`. Elixir entry point is `run_ls_pairs/1`; Rust and
Erlang mechanism code were unchanged. This validates this installed binary and
fixture on macOS, not all ls implementations, individual descriptor sensitivity,
arbitrary terminal dimensions or arbitrary applications. The fixture snapshots
are boundary checks, not proof against transient external mutations. Next bounded
candidate: echo on/off with the existing hello-world witness; not implemented here.
