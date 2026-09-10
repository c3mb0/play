# witness_001 — observed PASS

One constructed matched pair, no retries, on macOS 26.6.1 arm64.
Plan committed as `de83650`; implementation committed as `c270bb8` before the run.
Evidence: `receipts/witness-20260910T203307Z`.

Both cells ran the same hello_witness binary (SHA-256
`2b507457148c69b0f4d7eee258f7f8a1afce95a8a8550f4c654b17c820fb5a06`),
empty argv, exact environment/cwd, helper 0.3.0, fresh session and no controlling
terminal. Only the requested attachment changed from pipe to PTY slave. Frozen
termios/dimensions were used; no terminal state axis was added.

| Observation | Pipe | PTY |
| --- | --- | --- |
| Requested and actually written input | `hello\n` | `hello\n` |
| Raw output | `received: hello\n` | `input> hello\r\nreceived: hello\r\n` |
| Child exit | code 0, no signal | code 0, no signal |
| Input-request preparation after spawned receipt | 101.414 ms | 101.791 ms |

Timing policy was identical: wait 100 ms after receiving `spawned`, then prepare
the same write request, without waiting for a prompt. Actual scheduling differed
by about 0.377 ms; these measurements are not exact OS input-delivery times.
The witness branches on terminal attachment, not on elapsed time.

Interpretation: terminal attachment enabled the program's prompt. The extra
`hello` echo and CRLFs match the existing ECHO/ONLCR terminal configuration;
this attribution is separate from the preserved raw merged stream. No echo
removal, whitespace normalization, or arbitrary-output acceptance was used.

Both standalone v2 journals were complete with verified seals. Input observations
equal the requests; task definition and binary hashes matched. Both workers ended,
BEAM exited normally, and all six relay/guardian/subject PIDs were absent within
the three-second reclamation check. Total run duration was about 1.44 seconds.

Build, Rust formatting/Clippy, Python syntax checks, Erlang compilation, seven
EUnit tests and xref passed. The paired runtime check is the witness's behavioral
test. Existing helper/writer/recovery implementation was unchanged.

Claim earned: this apparatus can capture a known constructed behavioral flip
caused by terminal attachment with task content fixed. One pair establishes no
statistical repeatability, no claim about an unmodified application, and no
controlling-terminal, interactive-timing or terminal-matrix result.
