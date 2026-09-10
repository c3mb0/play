# ls_001 — unmodified application witness

Predeclared before running the subject. Use the installed /bin/ls, argv [],
cwd experiments/ls_001/fixture, containing exactly three empty regular files:
alpha, bravo, charlie. Environment exactly PATH=/usr/bin:/bin, LANG=C,
TERM=xterm-256color. No input bytes, no write or EOF command, no input delay.

Run three pipe-then-PTY-slave pairs through the Elixir experiment layer, at most
two pairs concurrently. Keep existing frozen 24x80 terminal configuration,
fresh-session policy, five-second session deadline and twenty-second pair bound.
Outer acceptance watchdog: 60 seconds. Zero automatic retries.

Prediction from the installed macOS ls(1), -C and -1 descriptions: default output
is columns on a terminal, one entry per line otherwise. Apple's public source
repository is https://github.com/apple-oss-distributions/file_cmds/tree/main/ls;
this is explanatory context, not proof of the installed binary's provenance.

Exact pipe stdout predicate: alpha\nbravo\ncharlie\n, empty stderr.
PTY predicate: one row, alpha then bravo then charlie, separated by one or more
ASCII spaces or tabs, followed immediately by CRLF. No other bytes permitted.
Horizontal spacing is deliberately not predicted exactly. Raw bytes are retained;
CRLF conversion alone cannot satisfy the behavioral flip. No colors or flags
are requested. The full environment omits COLUMNS and color-control variables.

Require matching executable/helper hashes, task definition except attachment,
environment, terminal configuration, requested topology and empty observed input;
verified complete receipts and zero child exits. Check fixture names/types/modes/
content hashes before and after the run and preserve both snapshots. Capture the
installed manual's relevant lines and /bin/ls hash. Check every reported process
absent within three seconds, order and maximum observed concurrency from journals.

Failures remain failures with raw receipts preserved: no predicate changes or
rerun to obtain a green result. This experiment tests the installed macOS ls and
this fixture only. It does not isolate individual stdio descriptors or add a new
terminal axis. Echo on/off is a subsequent, separate checkpoint.

## Explicit harness correction after first run

First run ls-20260910T210550Z (source 88c5d43) remains failed. Elixir recorded
three passing layout pairs, but Python compared uppercase Erlang SHA-256 text
with lowercase Python SHA-256 text and stopped before the post-run fixture and
bounded PID checks. The digest bytes are equal. No original artifacts change.

Correct that checker to compare decoded digest bytes, then execute ONE separately
identified validation run. This explicitly revises the no-rerun rule for this
identified harness defect, not for a subject mismatch. Keep every output predicate,
fixture, bound and subject definition unchanged. Preserve both runs and their
source commits; report two attempts, zero automatic retries. If the second run
fails, retain it and report the remaining limitation rather than tuning predicates.
