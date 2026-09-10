# width_001 — observed initial-width layout change

PASS: three matched installed /bin/ls pairs, both attached to a PTY slave, with
empty argv/input and the same environment/cwd/three-file fixture.

| Initial columns | Exact raw PTY output, escaped |
| --- | --- |
| 80, all pairs | `alpha\tbravo\tcharlie\r\n` |
| 8, all pairs | `alpha\r\nbravo\r\ncharlie\r\n` |

These are application-emitted bytes. No emulator wrapped the display, and no
resize or SIGWINCH command was sent. The prediction was declared before execution.
Native slave readback matched both requested configurations: only columns changed.
Rows, pixel dimensions, termios and topology stayed fixed. Pixel dimensions were
intentionally held fixed; this measures character-column reporting, not geometry.

[Manifest](../../receipts/width-20260910T212259Z/manifest.json) ·
[Report and raw receipts](../../receipts/width-20260910T212259Z/pairs/report.json).
Plan 7e9b6a2; runtime source 6fd4052b5db8c98090f3714581f743d9d0a17e6f.
One run, zero retries, 1.641 seconds within the 60-second watchdog. Six sealed
verified receipts, all zero exits, all eighteen reported PIDs absent within the
cleanup bound. Wide completed before narrow in each pair, max concurrency two.
Fixture names/types/modes/content hashes and /bin/ls hash matched before/after.

Six fixed-seed Elixir tests, compile with warnings as errors, formatting, Clippy
and Python syntax checks passed. New checks reject unchanged output, extra pixel
changes and missing readback. Existing runtime regressions passed:

- ls pipe/PTY: ls-20260910T212301Z
- echo on/off: echo-20260910T212302Z
- canonical on/off: canonical-20260910T212304Z
- hello-world normal/mismatch/execution-failure: elixir-20260910T212307Z

All evidence remains under receipts/. No Rust, Erlang or dependency changes were
needed. Reproduce with `make width-check`, or call run_width_pairs/1 through the
Elixir API with a fresh output directory.

Scope: this installed macOS ls, these three names and initial widths 80/8 only.
Boundary snapshots are not continuous filesystem monitoring. Setup readback is
not continuous terminal monitoring. Descendants, guardian death and other
platforms retain previous limits. Live resize/SIGWINCH is a separate future
checkpoint, not established by this result.
