# Frozen Phase A observation

Source: `receipts/reference-20260910T194106Z/` (macOS 26.6.1 arm64).
Captured before helper implementation; both probes exited 0.

| Observation | Pipes | macOS Terminal |
| --- | --- | --- |
| isatty, fd 0/1/2 | false/false/false | true/true/true |
| termios / winsize | errno 25 (ENOTTY) | available on all three |
| /dev/tty open | errno 6 (ENXIO) | succeeds |
| foreground pgrp | errno 25 | equals subject pgrp |
| dimensions | unavailable | 24 rows, 80 cols, 560 x 336 pixels |
| canonical / echo / isig | unavailable | all true |
| session leader | yes | no |

Interpretation: stdio terminal attachment and controlling-terminal membership
are separately observable dimensions. The reference shell job shares a session
with its shell and a foreground process group with the wrapper. A helper-created
session leader can match the declared terminal projection without matching this
ancestry. The full probe can still distinguish those processes.

The Terminal reference includes its actual control characters, speed, all four
flag words and pixel dimensions. These are the explicit configuration input to
the Rust gate; no host-default termios equivalence is assumed.

Artifacts are create-new, checksummed and read-only, with Git custody. This is
local tamper-evident preservation, not a hardware/WORM immutability guarantee.
