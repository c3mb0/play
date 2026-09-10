# echo_001 — one terminal-state variable

Three matched pairs of the existing hello_witness: PTY slave with ECHO on, then
PTY slave with ECHO off. No controlling terminal. Same executable, argv [], cwd,
explicit environment, input hello\n and 100 ms after spawned input policy.
Use existing frozen terminal configuration; change only ECHO in c_lflag and its
redundant echo boolean. macOS SDK sys/termios.h defines ECHO=0x8. Reject other
platforms for this configuration. Keep ICANON, ECHONL, all other flags, control
characters, speeds and dimensions unchanged. Frozen ECHONL is off.

Add Rust readback of slave termios and dimensions immediately after openpty,
before subject spawn; preserve it in spawned. It must equal the requested
configuration in each cell. This is setup-time observation, not continuous
monitoring or evidence of subsequent subject changes. The ECHO mask returned by
the native helper must match the experiment's platform-specific mask.

Expected exact echo-on output: input> hello\r\nreceived: hello\r\n OR
hello\r\ninput> received: hello\r\n (the existing two prompt/echo orders).
Expected exact echo-off output: input> received: hello\r\n.
Both subjects receive hello\n, retain their prompt, and exit zero without signal.
Raw bytes remain unchanged. This tests terminal driver echo, not an application
interactive-mode flip; both subjects see a terminal.

Require complete verified sealed receipts, matching input_written and subject/
helper/environment hashes, identical task and topology except the declared ECHO
bit, and observed settings matching each requested configuration. A CRLF-only
change, extra setting change, missing echo flip or missing observation fails.

Bound: five seconds per session, twenty per pair, max two pairs concurrently,
sixty seconds for external acceptance including three-second PID absence check.
Validate order/concurrency from journals. Zero automatic retries. Preserve failures;
any harness correction requires an explicit record and separate validation receipt.
No canonical/raw, resize, controlling-terminal, EOF or signal axis is added.
