# operator_001 — observed workshop result

PASS: six cases, six verified sealed session journals, thirteen intervention
requests, twenty known PIDs absent. One run, zero retries, 4.850 seconds. No
independent-watchdog emergency actions were needed. The fixture coordinator
explicitly terminated both intentional holders as part of the exhibits.

Plan 721fec1; runtime source 6c21133faa2b418e28fc158dee514bd7f105dbf8.
[Manifest](../../receipts/operator-20260910T213632Z/manifest.json) ·
[Take-home wishlist](../../OPERATOR-WISHLIST.md).

| Exhibit | Observation | Interpretation / limit |
| --- | --- | --- |
| input_wait | Silent cat had OS state Ss; write produced hello, EOF yielded zero exit, late write was rejected | Silence alone remains unknown |
| blocked_output | Guardian T; write_started but no write_finished; resume drained exactly 256 KiB and completed | Supports output backpressure; intent marker and ps do not identify a syscall |
| stopped | Subject Ts after STOP; CONT then API terminate; signal 9 observed and PIDs absent | External stopped-state evidence; API acknowledgement is separate from effect |
| held_output | Parent absent, holder alive under PID 1, child_exit event unavailable; holder termination released EOF and zero exit | Current child_exit reporting waits for stream closure |
| caller_death | Worker and child survived caller death; session ended by 1200 ms OTP timeout | Caller is not Port owner; deadline remained effective |
| worker_death_descendant | Direct chain absent, holder survived; explicit holder cleanup succeeded | Direct-child containment does not contain descendants |

Each case interpretation links its original session journal. OS snapshots and
intervention requests/responses are preserved separately, including the rejected
operation after session completion. No original journal was reopened to append
a late action. The outer SHA-256 manifest covers every artifact.

Validation: Rust build/fmt/Clippy, Python syntax, Elixir script compilation and
formatting, and all six existing Elixir unit tests passed. The new exhibit uses
the existing Erlang API and changes no production Rust-helper/Erlang/Elixir
mechanisms. Cargo.lock adds only operator_subject; dependency versions unchanged.

Reproduce: make operator-check. Custom subjects have process alarms and holders
an eight-second lifetime bound; OS utility waits and all observation loops are
bounded. The Python watchdog collects this run's reported PIDs and holder files,
checks executable paths before emergency intervention, and records any such
intervention as a failed run. It cannot discover arbitrary unreported descendants
or provide stable PID identity against reuse. Failure of that fallback was not
injected in this round. This is a citizen-lab exhibit, not a production process
supervisor, universal diagnostic or formal containment certification.
