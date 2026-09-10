# External Port protocol v1

Transport: 4-byte unsigned big-endian length, followed by UTF-8 JSON. Length must
be 1..1,048,576. Erlang uses `{packet, 4}` and `binary`; stderr is never merged
into the framed channel. Rust uses direct descriptor writes: buffered stdout
delayed events in the first ownership run, retained as failed evidence.

Every accepted command/event carries `v: 1`, `identity` (string `experiment`,
`cell`, `session`) and `seq`. Command and event sequences are separate consecutive
counters starting at 1. Identity cannot change. Events also contain `unix_ns`,
elapsed guardian `monotonic_ns`, `event`, and `data`.

The Erlang journal has its own receipt sequence and receive timestamps; it embeds
the unchanged helper event. Ordering is controller-observation order, not a claim
about simultaneous writes on different descriptors. Early malformed-frame
diagnostics may have null identity before a valid session is bound; these are
protocol rejections, not accepted session events.

## Commands

`spawn` exactly once, with `spec`:

```json
{
  "executable":"/absolute/executable",
  "argv":[],
  "environment":{"LANG":"C","TERM":"xterm-256color","PATH":"/usr/bin:/bin"},
  "cwd":"/absolute/directory",
  "attachment":"pipe",
  "terminal":{}
}
```

`argv` excludes argv[0], which is the executable. Environment is cleared and
replaced exactly. Attachment is `pipe`, `slave`, or `ctty`; all create a fresh
session. PTY modes require `terminal.termios` and `terminal.dimensions` with the
same platform-specific fields as gate_001. `ctty` additionally acquires the
controlling terminal and foreground group. Invalid modes/settings are errors.

* `write`, `hex`: byte-exact input, queued with a 1 MiB limit. `write_queued` is
  acceptance; `input_written` records bytes actually written.
* `close_stdin`: pipe only, after queued bytes drain. A PTY has no independent
  stdin half-close; the request is explicitly rejected.
* `terminate`: send SIGKILL to the owned child. `signal_sent` records the operation;
  `child_exit.signal` is the observed wait status.
* `status`: report whether a subject has been spawned.

Resize, arbitrary signals, process-group controls and matrix commands remain
deferred. Protocol errors terminate the session after cleanup; no invisible retry.

## Events and receipts

`spawned` (subject, guardian and relay PIDs, attachment, helper version), `stdout`,
`stderr`, `pty_output` (hex bytes), `write_queued`, `input_written`, `stdin_closed`,
`stream_end`, `signal_sent`, `status`, `child_exit`, `error`. OS errors retain
numeric errno when present and the OS message. PTY stdout/stderr are merged.

OTP adds `session_start`, `port_open`, ordered `command` records, `helper_event`,
`helper_exit`, `timeout`, fault-injection records, and one terminal journal entry
on covered worker/helper paths. The independent receipt writer records worker
death. BEAM/receipt-writer death can leave an unsealed partial journal; it remains
evidence and is not falsely completed on restart.

Phase D adds self-contained receipt header schema 2 and explicit snapshot recovery
without changing this wire protocol. See [receipt semantics](../RECEIPTS.md).

## Ownership and bounds

```text
session_worker --Port pipes--> relay --pipes--> guardian --owns/waits--> subject
```

The relay forwards bytes only. The guardian is the same Rust binary invoked with
`--guardian`; it owns the child and PTY. Relay death closes its command pipe;
guardian detects EOF, kills/reaps the child, and exits. Worker death closes the
Port and propagates EOF through the relay. This does not rely on SIGHUP.

OTP owns a 1..60000 ms session deadline, followed by 1500 ms for termination
response. Rust polls nonblocking session I/O, has a 1-second cleanup/drain bound,
and caps input/output queues at 1 MiB each. The relay waits at most 1 second for
guardian exit after stdout EOF. Backpressure is never silently dropped.

The test gives process reclamation three seconds and records it separately from
session failure: a terminal event alone is not cleanup proof. Guardian SIGKILL,
escaped descendants, malicious fork trees, stalled kernel I/O and recovery of
incomplete journals are outside this gate. This is direct-child containment on
the tested Mac, not a general process sandbox.

References: Erlang [Port ownership](https://www.erlang.org/doc/system/c_port.html),
[open_port options](https://www.erlang.org/doc/apps/erts/erlang.html#open_port/2),
and [native JSON](https://www.erlang.org/doc/apps/stdlib/json.html).

## Setup-time terminal readback

The framed helper now adds `terminal_observation` to `spawned`: null for pipes;
for PTYs, an object with phase `slave_before_spawn`, native `echo_mask`, and
`configuration` containing termios and dimensions. Rust obtains these with
`tcgetattr` and `TIOCGWINSZ` on the slave after openpty, before child spawn. Readback
failure fails setup through the existing OS error path. No process is spawned
when that readback fails. This is an additive protocol-v1 field; earlier receipts
may lack it. The helper binary fingerprint distinguishes implementations.

The configuration flag words remain authoritative; boolean fields are decoded
summaries. The echo experiment changes both c_lflag and its echo summary, then
requires observed configuration equality. The readback does not monitor later
subject-initiated terminal changes or establish cleanup success.

Canonical readback also reports native `canonical_mask`, `vmin_index` and
`vtime_index`. These additive identifiers let the experiment verify its
platform-specific flag/cc interpretation. They do not change terminal setup or
add a raw-mode command. Older receipts may omit them.
