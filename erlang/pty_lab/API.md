# Session caller contract

`pty_session` is the control-plane boundary. Call from the process that will await
the result. Start `pty_lab` first. Definitions use Erlang option keys and the
protocol's binary-key `spec` map; see the existing witness experiment.

* `start_session(Options) -> {ok, Handle} | {error, Reason}`
* `send_input(Handle, Binary) -> ok | {error, Reason}`
* `close_stdin(Handle) -> ok | {error, Reason}` (pipe only)
* `terminate(Handle) -> ok | {error, Reason}` (direct-child SIGKILL request)
* `await_event(Handle, EventNameBinary, TimeoutMs) -> {ok, Event} | {error, event_timeout}`
* `await_result(Handle, TimeoutMs) -> {ok, Result} | {error, await_timeout | result_unavailable}`

Handle contains full identity, worker PID, caller monitor, receipt filename and
owner. Identity has binary run/experiment/cell/session fields. If low-level legacy
experiments omit run, it defaults to the receipt parent directory name. The writer
keys by all four fields and reserves used identities for its lifetime. The file
itself always uses exclusive creation, including across writer restarts.

The caller owns result consumption: await once from the originating process.
An await timeout neither cancels nor retries the session; its own OTP deadline
continues. Event notifications and terminal results use the full key. Session
startup/file errors return errors before a subject is spawned; later failures
arrive as results. Calls to a closed worker return `session_closed`.

Result fields:

* `identity`, `receipt` (Erlang filename), `outcome` (binary).
* `child_exit`: observed code/signal map or `null` if unobserved.
* `receipt_status`: `sealed` or `partial`.
* `cleanup`: `state = unverified` plus reported PIDs when known. A result is not
  itself an OS process-absence check; experiments verify that separately.
* `details`: observed helper exit, rejection/error or interruption details.

`completed` means the session observed child completion, not that its code was 0.
Explicit failure outcomes include helper_failure, helper_start_failure,
helper_error, protocol_failure, port_send_failure, receipt_failure,
receipt_writer_failure, timeout and cleanup_timeout. Error messages preserve the
operation/reason. A refused Port send remains a recorded request, never a claimed
input write. Port queues use 64/128 KiB busy watermarks and nosuspend sends.

The shared writer contains per-session open/write/seal failures. A failed write
leaves partial evidence and aborts that worker. If the writer dies, every worker
monitoring that exact instance closes its Port and returns a partial result.
Supervision can restart the writer for new sessions; existing sessions are never
replayed. Offline recovery remains explicit and does not restore writer state.

Legacy experiment code may still use session_worker/session_sup directly and
receive its session-name notifications. New callers must use pty_session; external
receipt annotations use a worker PID (or the full identity key), never a short
session name. No experiment policy is implemented by this API.
