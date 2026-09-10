# isolation_001 — observed PASS

Evidence: `receipts/isolation-20260910T204605Z`, runtime source `e69b852`.
Six bounded scenarios passed in about 1.66 seconds, without automatic retries:
full-identity isolation/duplicate rejection, helper murder, receipt-open failure,
receipt-FD write failure, real Port backpressure, and shared-writer death/restart.

Concurrent sessions reused cell/session names in different experiments without
mixed outputs. Every fault scenario kept its healthy sibling alive and able to
finish. Stopping a real helper caused nosuspend Port refusal; the session returned
port_send_failure, then the resumed relay/guardian/subject were reclaimed.
Writer death yielded partial results for both active sessions and reclaimed their
reported PIDs; a fresh session succeeded with the restarted writer. No replay.

The receipt write test deliberately closed one writer-owned raw FD via OTP system
inspection; it is not a physical disk-full test. Terminal results honestly mark
cleanup unverified; the experiment separately checked OS process absence.

Public API regression: hello-world pair passed through pty_session in
`receipts/witness-20260910T204642Z`. All nine ownership sessions passed in
`receipts/ownership-20260910T204644Z`; all 14 receipt/recovery checks passed in
`receipts/receipt-20260910T204646Z`. Seven EUnit tests and xref passed. No Rust
mechanism changes were needed. This checkpoint is committed before Elixir work.
