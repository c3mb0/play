# canonical_001 — line delivery versus byte delivery

Three matched PTY-slave pairs, canonical on then off, echo off in BOTH. Existing
terminal configuration, changing only ICANON (macOS SDK value 0x100) and its
redundant canonical summary. Existing VMIN=1, VTIME=0 stay unchanged. No raw-mode
preset: signals, newline processing and all other terminal state stay fixed.
Reject other platforms. Native helper readback must verify the applied settings,
ICANON mask and control-character indices in every receipt.

New tiny byte_witness, identical executable/argv []/environment/cwd across cells:
1. Flush READY\n and open a 400 ms poll window for one stdin byte.
2. If readable, read exactly one byte via libc::read (no application line buffer).
   If not, retain NONE. Wait until the original window deadline in either case.
3. Flush WINDOW NONE\n or WINDOW 68\n.
4. Collect the remaining bytes with bounded readiness waits, require total h\n,
   print FINAL 680a\n, and exit zero. Poll/read errors are explicit failures.

Identical controller policy, driven by subject phase markers:
wait for READY, send h, observe its input_written acknowledgement;
wait for WINDOW line, record it, then send newline. No branching on the window
result to choose bytes or delays. Both phases have fixed one-second controller
waits. This is a matched timing POLICY, not equal wall-clock delivery. The
subject's fixed 400 ms window is the observation interval, not an adaptive wait.

Prediction, exact raw PTY bytes (ONLCR remains enabled):
canonical on:  READY\r\nWINDOW NONE\r\nFINAL 680a\r\n
canonical off: READY\r\nWINDOW 68\r\nFINAL 680a\r\n
Thus the canonical cell has no readable byte during the early window, while the
noncanonical cell reads h before newline. Both finally receive h\n. This tests
input readiness/delivery in this bounded window, not a universal latency promise.

Acceptance: complete sealed verified receipts, zero child exits, same executable/
helper/environment and input bytes, exact output, exactly the declared setting
change, setup readback equal to requests. Verify receipt ordering: h write ack,
window observation, newline write request/ack, terminal result. Preserve actual
window/read timing from probe diagnostic output separately if included before
source commit; never normalize raw bytes or tune expectations after a run.

Five seconds/session, twenty/pair, max two concurrent pairs, sixty-second outer
watchdog including three-second PID absence check. Three pairs, no automatic
retries. Preserve failures; any correction gets an explicit record and new receipt.
No EOF, resize, signal, controlling-terminal or factorial matrix is introduced.
