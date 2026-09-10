# width_001 — initial terminal width

Three matched pairs of installed /bin/ls, argv [], empty input, same cwd
experiments/ls_001/fixture with the three empty files alpha, bravo, charlie.
Same exact environment PATH=/usr/bin:/bin, LANG=C, TERM=xterm-256color; no COLUMNS,
color variables or formatting flags. PTY slave attachment in BOTH cells.

Initial widths 80 then 8 columns. Change only dimensions.cols in the existing
frozen configuration. Rows, pixel dimensions, termios, fresh-session policy and
all task content remain identical. Pixel dimensions deliberately stay fixed:
this tests the reported character-column count, not physical screen geometry.
Native setup readback must match each requested configuration completely.

Prediction: at 80 columns, ls emits one row, alpha then bravo then charlie,
separated by one or more ASCII spaces/tabs, ending CRLF and no other bytes.
At 8 columns, ls emits exactly alpha\r\nbravo\r\ncharlie\r\n. Names fit individually
but cannot fit side-by-side within 8 columns. This follows the local ls(1)
terminal-column behavior and uses the already observed 80-column case as control.
Raw output distinguishes application-generated line breaks from screen wrapping;
no terminal emulator is involved. No dynamic resize or SIGWINCH is sent.

Require same executable/helper/environment fingerprints, argv/cwd/input, topology
and all requested settings except cols; verified complete sealed receipts, zero
child exits, empty observed input, setup readback matching both requests. Preserve
fixture names/type/mode/content snapshots and subject hashes before/after.

Three pairs, wide before narrow in each, max two concurrent pairs; five seconds
per session, twenty per pair, sixty-second external watchdog including bounded
three-second PID absence check. Verify order and concurrency from journals.
No automatic retries or normalization. Retain failed runs; any harness correction
requires an explicit record and new receipt. No new probe or OS mechanism needed.
Only this installed macOS binary and fixture are claimed; no factorial matrix.
