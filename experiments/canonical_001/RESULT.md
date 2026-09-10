# canonical_001 — observed input-delivery distinction

PASS: three matched PTY-slave pairs, canonical on then off, echo off in both.
All six subjects ultimately received h\n and exited zero without a signal.
The same byte_witness executable, argv, cwd, explicit environment and phase-driven
input policy were used in every cell.

| Condition | Exact raw PTY output, escaped |
| --- | --- |
| ICANON on, all pairs | `READY\r\nWINDOW NONE\r\nFINAL 680a\r\n` |
| ICANON off, all pairs | `READY\r\nWINDOW 68\r\nFINAL 680a\r\n` |

During the probe's fixed 400 ms early window, the canonical cell had no readable
byte. The noncanonical cell read h before the controller sent newline. The probe
uses poll plus one-byte libc::read, avoiding application line buffering. It holds
the WINDOW report until the original deadline in both modes. Only after observing
that report does the controller send newline, regardless of the reported result.

[Manifest](../../receipts/canonical-20260910T211835Z/manifest.json) ·
[Report and raw receipts](../../receipts/canonical-20260910T211835Z/pairs/report.json).
Plan f1db193; runtime source 14c45ea5834d9f540fe071aa2459ebb4cbea0f9e.
One run, zero retries, 3.380 seconds under the 60-second watchdog. Six receipts
were sealed and verified; all eighteen reported PIDs were absent within the
three-second cleanup check. Maximum observed concurrency two; each control
finished before its treatment began.

Journal checks confirm READY before the h write, h acknowledgement before the
WINDOW output and controller observation, then newline write/ack before terminal
completion. Observed h-acknowledgement-to-WINDOW-observation intervals ranged
396.565–405.002 ms. These are controller-side receipt intervals, not precise probe
poll durations or kernel delivery timestamps. Scheduling was not normalized.

Native slave readback matched each requested configuration. c_lflag changed from
536872387 to 536872131, xor 256 (ICANON); ECHO stayed off. VMIN=1 and VTIME=0,
control-character indices, every other flag, speeds and dimensions stayed fixed.
This is a noncanonical input comparison; a full raw-mode preset was not applied.

## Validation and limits

Five fixed-seed Elixir tests, compile with warnings as errors, formatting, Clippy
and Python syntax checks passed. New checks reject absent early-byte delivery,
an extra VMIN change and missing native ICANON metadata. Runtime regressions:

- echo pairs: echo-20260910T211839Z
- hello-world normal/mismatch/execution-failure suite: elixir-20260910T211840Z
- unmodified ls pairs: ls-20260910T211845Z

All passed and retain separate receipts. Erlang lifecycle code was unchanged;
Rust helper only added native ICANON/VMIN/VTIME identifiers to existing readback.
Cargo.lock adds the byte_witness package without changing dependency versions.
Reproduce with `make canonical-check`.

This establishes readiness/delivery within this bounded window on macOS, not a
universal latency guarantee. Setup readback is not continuous monitoring; receipt
phase timing is not kernel timing. Guardian death, descendant containment, other
platforms, EOF, signals and resize remain outside this checkpoint. Next candidate:
initial terminal width with the existing unmodified ls subject, predeclared first.
