# ownership_001 — predeclared Phase C gate

Scope: OTP supervision, one session worker per external Port, a versioned framed
protocol, bounded timeouts, durable ordered session journals, and crash cleanup.
Keep Phase A/B evidence unchanged. No behavioral witness or terminal matrix.

Ownership: BEAM session_worker -> Port relay -> Rust guardian -> direct subject.
The guardian is a separate invocation of the same Rust executable. It alone
holds Child ownership, observes relay-pipe EOF and kills/reaps the subject.
This extra process is required to survive relay SIGKILL on macOS without relying
on SIGHUP behavior or racing a PID report. Guardian SIGKILL and descendants are
outside this gate. Worker kill closes its Port; relay EOF reaches the guardian.

Predictions/pass criteria:

1. One unchanged probe under pipe and controlling PTY through OTP reports the
   expected isatty difference. Same executable, argv, environment, cwd, no input.
2. Framing handles fragmented/multiple packets; bad version/oversized messages
   are rejected explicitly. All session events include identity, sequence and time.
3. Input write and pipe EOF work byte-for-byte, including NUL/non-UTF8 bytes.
4. A subject that ignores SIGHUP remains alive before injection. Murder relay
   with SIGKILL: worker records helper failure and ends; guardian and subject
   disappear within three seconds; BEAM/supervisors remain alive.
5. Kill worker: independent journal owner records worker failure; helper, guardian
   and subject disappear within three seconds. No worker restart/replayed run.
6. OTP timeout terminates/reaps a live subject, recording timeout distinctly.
7. A fresh normal session succeeds after failure cells, in the same BEAM.

Each session <= 5 seconds plus <= 3 seconds cleanup. Entire test <= 60 seconds.
No automatic retry. New exclusive evidence directory per invocation; failures
remain. Observation journals are append-and-sync, then sealed with checksum and
read-only permissions; comparisons/assertions live separately.
