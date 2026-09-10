# elixir_001 — first experiment API, after isolation_001 passes

Elixir owns definitions, matched-pair scheduling, predicates and comparison
reports. It calls the frozen Erlang API; it owns no OS descriptors, supervision,
session deadline mechanism or receipt writing. Use ordinary functions/maps, no DSL.

Acceptance: run three hello-world pairs, declared pipe-then-PTY order per pair,
max two concurrent pairs (one cell active per pair). Check matching executable,
argv/env/cwd/input/config, verified receipts, exact declared raw-output predicates
and zero child exits. Distinguish pass, mismatch and execution_failure.

A separate three-pair experiment sends the wrong line to pair 2 in BOTH cells.
This known mismatch preserves matching task input while violating the declared
hello expectation. Continue remaining pairs; preserve all receipts. Also test
execution_failure classification with a bounded invalid-executable case. No
automatic retries or normalization; no terminal matrix expansion.

Each session <= 5 s; each experiment externally bounded <= 60 s. Run report
contains definition, order/concurrency/continuation policy, all cell identities,
receipt paths and hashes, comparisons and precise failures. Keep observations
in Erlang journals and interpretations in an exclusive checksummed Elixir report.
