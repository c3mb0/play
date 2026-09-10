# elixir_001 observed result

PASS on macOS 26.6.1 arm64, Elixir 1.20.4 and OTP 29.0.6. Runtime source was
committed as `b9b3c8feaed28bbff4dbda2852d34edd604bfabb` before execution.

[Manifest](../../receipts/elixir-20260910T205341Z/manifest.json) records one run,
zero retries, eighteen sessions and 4.674 seconds within the sixty-second bound.

| Experiment | Pair outcomes | Experiment outcome |
| --- | --- | --- |
| Normal | pass, pass, pass | pass |
| Wrong input in both cells of pair 2 | pass, mismatch, pass | anomalies |
| Invalid executable in both cells of pair 2 | pass, execution_failure, pass | anomalies |

Reports: [normal](../../receipts/elixir-20260910T205341Z/normal/report.json),
[mismatch](../../receipts/elixir-20260910T205341Z/mismatch/report.json),
[execution failure](../../receipts/elixir-20260910T205341Z/execution-failure/report.json).
The outer acceptance passes because the deliberate anomalies remained anomalies.

All eighteen journals were sealed and independently hash-verified, including
failed executions. Fifty reported PIDs were absent after bounded cleanup checks.
Receipt timestamps confirmed pipe completion before PTY start for every pair;
maximum observed simultaneous sessions was two in each experiment. Existing
output-directory reuse was rejected with report bytes unchanged.

Compilation with warnings as errors, formatting, the fixed-seed classification
unit test, Clippy and Python syntax checks passed. Before introducing Elixir,
the six-scenario isolation gate and witness/ownership/receipt regressions passed:
`isolation-20260910T204605Z`, `witness-20260910T204642Z`,
`ownership-20260910T204644Z`, `receipt-20260910T204646Z` under receipts/.
That plumbing milestone was published as c3e2e08 first.

Reproduce with `make elixir-check`; each invocation preserves a new evidence set.
The Elixir API owns interpretation only. Raw observations remain Erlang receipts.
This establishes the constructed hello-world case on macOS, not arbitrary
application behavior, identical scheduling, descendant containment or guardian
SIGKILL recovery. No additional terminal variables were introduced.
