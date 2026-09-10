# Session receipts and recovery

Receipt header schema 2 is self-contained. The journal envelope and helper wire
protocol remain version 1. Existing historical receipts are never rewritten.

The first `session_start` records:

* Run ID and session identity (experiment/cell/session in every envelope).
* Full requested executable, argv, environment, cwd and attachment configuration.
* Executable/helper paths, sizes and pre-spawn SHA-256 hashes, plus the helper's
  own version/protocol response. Read/query failures remain explicit errors.
* Environment fingerprint: UTF-8 keys sorted bytewise; each key then value encoded
  as a four-byte unsigned big-endian byte length followed by those bytes; SHA-256
  over the concatenated fields. This avoids delimiter ambiguity and Erlang-only
  serialization. Empty environment hashes an empty byte sequence.
* Requested session/foreground topology, deadline, zero retries, input policy.
* OS type/version, architecture, OTP/system versions and loaded Erlang module MD5
  identities. Module MD5 is a code identity, not cryptographic custody.

File fingerprints are measured before spawn, not an assertion that executable
bytes could not change between hashing and exec. Actual topology, byte writes,
output, signals and child exit are separate ordered events. A command entry means
requested; `input_written` means bytes actually written. Missing events remain
unknown. `completed` is a session lifecycle outcome, not necessarily exit code 0.

Each event has a session sequence and wall/monotonic timestamp. Helper events keep
their own identity, sequence and timestamps inside the receipt. Normal completion
or covered helper/worker failure appends one `session_terminal`; the writer syncs,
closes, creates an exclusive `.sha256` companion, and makes both files read-only.
Copying a journal and companion is enough to inspect and verify that session.

## Explicit recovery

Recovery is a snapshot, not resumed execution or an in-place log repair. In an
Erlang VM with the compiled application on its code path:

```erlang
application:ensure_all_started(crypto).
receipt_recovery:recover("/absolute/session.jsonl", "/absolute/new-recovery-dir").
```

The destination must not exist. The operation reads a regular journal of at most
16 MiB, observes source file metadata before/after reading, and writes:

* `snapshot.jsonl`: every original byte, including a torn/corrupt suffix.
* `source.sha256`: the original seal bytes, if present.
* `recovery.json`: an explicitly labelled interpretation with offsets and status.
* `SHA256.json`: hashes of the recovery artifacts.

All newly written files use exclusive creation, sync, and read-only permissions.
No source byte, seal, permissions or event is changed. An interrupted recovery
may leave an incomplete destination; rerunning into that directory is rejected.

Classification and integrity are separate:

| Classification | Meaning |
| --- | --- |
| `complete` | Valid ordered journal ends with a recorded terminal event. |
| `incomplete` | No terminal event was recorded; outcome remains `unknown`. |
| `quarantined` | Invalid record/order/identity/metadata, post-terminal data, changed source metadata or bad/unreadable seal. |

Integrity is `verified`, `absent`, `mismatch`, `malformed`, or `unreadable`.
Complete-but-unsealed is reported as `complete` + `absent`; it is not historical
integrity proof. A complete JSON record without its final newline is an uncommitted
tail. A malformed newline-terminated record is corruption. Recovery stops at the
first invalid record; it never skips forward to a later terminal event. The raw
suffix is always retained. Legacy headers can be inspected, but are labelled
`metadata_complete: false` rather than retroactively populated.

The report includes valid-prefix bytes/event count, trailing bytes, first error,
last observed time, and terminal data only if a valid terminal record existed.
It does not infer process liveness or why writing stopped. Stable file metadata
during capture does not prove that a writer is dead or that the source was
historically authentic. SHA-256 and read-only files provide local tamper evidence,
not WORM storage, remote attestation or power-loss durability.

## Verified checkpoint

Run `make receipt-check` for the bounded Phase D experiment. It captures a normal
receipt, verifies a detached copy, then kills a real BEAM after a SIGHUP-ignoring
subject is ready. A fresh BEAM recovers the partial journal. Corruption cases are
explicitly synthetic derivatives of the normal journal; they are not represented
as observed OS failures.

See [results](experiments/receipt_001/RESULT.md) and the
[recorded run](receipts/receipt-20260910T202559Z/manifest.json).
Automatic replay, writer-state restoration, power-loss testing, guardian SIGKILL,
descendants and non-macOS runtime behavior remain out of scope.

Implementation references: Erlang [file operations](https://www.erlang.org/docs/29/apps/kernel/file.html)
and [module identity](https://www.erlang.org/doc/system/modules.html#module_info-0-and-module_info-1-functions).
