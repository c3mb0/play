# isolation_001 — plumbing boundary before Elixir

Implement identity keys containing run/experiment/cell/session; reject duplicate
active/used keys without damaging another journal. Convert receipt and Port I/O
failures to explicit results. If the shared receipt writer dies, existing workers
close their Ports and fail with partial receipts; supervision may restart the
writer but must never replay sessions.

Freeze a caller API: start_session, send_input, close_stdin, terminate,
await_result. A handle binds identity, worker, receipt and caller monitor. Results
separate session outcome, child exit, receipt sealing and cleanup evidence.
An await timeout does not silently cancel/retry the session. Input waits and
session deadlines remain bounded. Existing low-level experiments stay supported.

Acceptance (each cell <= 5 s + 3 s cleanup, entire run <= 60 s):

* Two concurrent sessions may use the same session/cell names in different
  experiments and produce unmixed receipts.
* Duplicate full identity is rejected while the original finishes normally.
* Helper SIGKILL, receipt open error, and a closed receipt FD each affect only
  the selected session; a concurrently live sibling finishes successfully.
* Stop a helper and fill its real Port until nosuspend rejects a send; classify
  backpressure explicitly, resume the helper, and reclaim it. Bound writes and
  bytes. Closed-session calls return errors without crashing the caller.
* Kill the receipt writer with active sessions: all fail explicitly and reclaim
  their OS resources; old journals stay partial; a fresh session succeeds after
  the writer restarts. No automatic replay.
* Existing hello-world pair runs through the public API; ownership and receipt
  regressions pass once after changes. Commit/push this checkpoint before Elixir.

Failure evidence is retained. Descriptor closure is a deliberate I/O-failure
injection, not a claim of physical disk-full testing. Fault test code may inspect
OTP state; production code gets no test-specific branches.
