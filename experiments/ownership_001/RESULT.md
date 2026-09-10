# ownership_001 result

Observed PASS on macOS 26.6.1 arm64, Rust helper 0.2.0, OTP 29.0.6, rebar3 3.27.0.

| Cell | Observed terminal outcome | Cleanup evidence |
| --- | --- | --- |
| pipe/slave/ctty probes | completed; expected TTY/controlling-TTY distinctions | normal exits |
| binary input | completed; `00ff0a410d42` round-tripped exactly | normal exit |
| relay SIGKILL, pipe | helper_failure, exit 137 | relay/guardian/subject absent within 3 s |
| relay SIGKILL, ctty | helper_failure, exit 137 | relay/guardian/subject absent within 3 s |
| worker kill | independent writer recorded worker_failure | relay/guardian/subject absent within 3 s |
| OTP deadline | timeout, observed subject signal 9 | relay/guardian/subject absent within 3 s |
| post-failure session | completed in the same BEAM | no remaining session workers |

Evidence: `receipts/ownership-20260910T195848Z`. The nine-session run took about
2.08 seconds including BEAM startup and checks. A SIGHUP-ignoring subject was
observed ready before every deliberate kill. Root supervisor, session supervisor
and receipt writer remained alive. Process checks use kill(pid, 0); PID reuse
would conservatively fail the check. They do not prove containment of descendants.

Protocol evidence: `receipts/protocol-20260910T195847Z`. Prompt replies passed for
fragmented/coalesced frames; wrong version, oversized/zero length and invalid
JSON produced explicit error events. EUnit additionally checked decoder identity,
sequence, version and invalid-JSON rejection. Rust checked all 256 byte values
through hex encoding/decoding. No retries occur within these runners.

The preceding failed run (`ownership-20260910T195717Z`) exposed buffered stdout
delaying events. The new source uses direct protocol descriptor writes. That
failure and its incomplete journal remain sealed in the enclosing run evidence.

Regression: `receipts/gate-20260910T200311Z` passed the original five-cell gate
using helper 0.2.0 and the original frozen probe hash. Build, formatting, Clippy,
Rust tests, Erlang compilation with warnings as errors, EUnit, xref and Python
syntax checks passed. Xref has named exemptions for external API/MFA callbacks;
there is no blanket suppression. No residual helper/lifetime-probe process was
found in the final process inventory.

Interpretation: the external Port boundary contains the tested relay/worker
failures, and the guardian provides direct-child reclamation independent of HUP.
This does not establish guardian-kill containment, descendant cleanup, journal
recovery after BEAM death, Linux behavior or a behavioral attachment witness.
