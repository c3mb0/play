# operator_001 — a take-home operator workshop

One bounded round, MIT. No generalized debugger, approval engine or production API.
Five questions: what was inherited; why hasn't this finished; which bounded action
can I take; what survived cancellation; can I rehearse failure safely?

Existing observations: launch hashes/spec, native pre-spawn PTY state, process IDs,
ordered wire/input/output/exit events and immutable receipts. Missing: generic
wait-reason inference, full descriptor inventory, immediate child-exit vs stream
EOF separation, descendant containment, explicit caller-to-session lifetime rule.

Six sequential exhibits, fresh sessions, no automatic retries:
1. input_wait: /bin/cat, no initial input; sample silence and OS state. Session-only
   diagnosis UNKNOWN, alternatives input wait/other blocking/scheduling. Write
   hello\n, observe acknowledgement/output, close pipe stdin, observe zero exit.
   A subsequent write to the finished handle must be rejected session_closed.
2. blocked_output: cooperative operator_subject flood announces READY, sleeps
   400 ms, records write_started independently, writes 256 KiB to stdout, records
   write_finished. Stop its guardian before write_started, observe OS stopped
   state, wait for write_started and check no write_finished after 100 ms. Resume
   guardian, require full output and zero exit. This supports backpressure; silence
   alone still yields UNKNOWN. Side-channel intent is not proof of current syscall.
3. stopped: a bounded hold subject, STOP direct child, confirm OS T state, CONT,
   then request public-API termination. Distinguish accepted request, receipt exit
   signal and independently checked absence. No claim the session API signals it.
4. held_output: subject spawns a bounded holder inheriting stdout/stderr; parent
   exits after input. Confirm parent absent and holder alive while child_exit is
   not yet delivered. Independently terminate holder; require EOF/completion and
   direct child zero exit. Record transcript-only UNKNOWN and external evidence.
5. caller_death: caller task starts a hold subject, then coordinator kills caller.
   Sample worker and child survival, then let a 1200 ms OTP deadline clean up.
   This tests caller death, not Port-owner death; coordinator reads sealed receipt.
6. worker_death_descendant: parent + inherited-output holder; kill session worker.
   Verify direct child/helper/guardian absence within 3 s, holder survival. Perform
   independent holder cleanup and verify absence. This exposes containment limit.

All custom subjects have 10-second process alarms; holders have an 8-second bound.
Holder PIDs are synced to unique case files before READY, letting the independent
Python watchdog clean them up even if BEAM fails. Python's final cleanup scans
only this run's known PIDs; it verifies process identities before intervening.

Each session <=5 s except explicit 1200 ms caller case; each await <=3 s; OS utility
calls <=1 s; outer run <=60 s including independent cleanup. Guardians stopped by
this fixture are resumed in finally blocks. Keep request/action/effect records
separate, with exact session identity, target, preconditions, declared deadline,
raw responses and evidence references. Preconditions are observations, not atomic
OS compare-and-swap guarantees. Safety cleanup does not count as session success.

Pass = all predeclared observations, verified sealed receipts, all known PIDs
absent after cleanup and explicit unknown/limits. Preserve any failure. No repair
or automatic replay of observations. Produce OPERATOR-WISHLIST.md with five ranked
capabilities and concrete evidence. Stop after documentation, commit and push.
