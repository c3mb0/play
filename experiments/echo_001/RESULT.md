# echo_001 — observed terminal echo flip

PASS: three matched PTY-slave pairs, same hello_witness binary, argv, environment,
cwd, input hello\n and 100 ms input policy. Both cells remain terminal-attached.
One run, zero retries, six sealed verified receipts, 2.012 seconds. All eighteen
reported PIDs were absent within the three-second cleanup check. Observed maximum
concurrency was two; each echo-on cell finished before its echo-off partner began.

[Manifest](../../receipts/echo-20260910T211145Z/manifest.json) ·
[Raw comparisons](../../receipts/echo-20260910T211145Z/pairs/report.json).
Predeclared plan commit 79e4855; runtime source caaa30741ebf2795a4ffbc49dfaff1f8d166d2cd.

| Condition | Exact observed output, escaped |
| --- | --- |
| Echo on, pairs 1 and 2 | `hello\r\ninput> received: hello\r\n` |
| Echo on, pair 3 | `input> hello\r\nreceived: hello\r\n` |
| Echo off, all pairs | `input> received: hello\r\n` |

Both echo-on orderings were predeclared, not normalized after observation. All
subjects received exactly hello\n and exited zero without a signal. Removing
terminal echo leaves the application prompt and reply intact. This is a terminal
driver effect; application interactive-mode selection is unchanged.

Rust read slave termios and dimensions after openpty and before spawning each
subject. Readback matched each requested configuration exactly. Observed c_lflag
was 536872395 with echo and 536872387 without: xor 8, the native ECHO mask.
All other flags, control characters, speeds and dimensions matched. ICANON stayed
on; ECHONL stayed off. The echo boolean is a redundant decoding of the flag word.

The report's inherited `pipe_output` predicate key denotes the first/control cell
for this experiment; its actual attachment and condition are explicitly recorded
as slave/echo_on. Both output streams here are PTY output, with stderr merged.

## Validation and limits

Four fixed-seed Elixir tests, seven EUnit tests, xref, compilation with warnings
as errors, formatting, Clippy and Python syntax checks passed. New comparison
checks reject extra terminal changes, missing readback and an absent echo flip.
Runtime regressions also passed with the updated helper:

- hello-world normal/mismatch/execution-failure: elixir-20260910T211147Z
- three unmodified ls pairs: ls-20260910T211152Z
- nine-session ownership/failure gate: ownership-20260910T211154Z
- fourteen receipt/recovery checks: receipt-20260910T211156Z

All evidence is under receipts/. Reproduce this checkpoint with `make echo-check`.
Readback is setup-time observation, not continuous monitoring. Exact scheduling,
individual descriptor effects, guardian death, descendant containment and other
platforms remain outside the claim. Only ECHO was varied; no other terminal axis
was added. Next candidate: canonical line delivery versus byte delivery, using a
byte-reading witness so application line buffering does not hide the distinction.
