# witness_001 — hello-world ping-pong, predeclared

Constructed witness: if stdin is a terminal, write and flush `input> `. Read one
newline-terminated UTF-8 line; print `received: ` followed by that line; exit 0.
No other terminal-dependent branch, random seed, environment lookup or timing.

Matched pair: pipe then PTY slave-only. Both use a fresh session, no controlling
terminal, same absolute executable/argv/environment/cwd, same helper binary and
5000 ms session deadline. PTY termios/dimensions are copied unchanged from the
frozen gate_001 configuration. No new terminal state variable is introduced.

Input: exactly `hello\n` once, 100 ms after receipt of `spawned` in each cell.
Do not wait for a prompt to decide when/what to send. Record actual elapsed time
and actual `input_written` bytes. Do not close stdin: the newline completes the
read on both attachments. Scheduling is measured, not claimed identical.

Predictions:

* Pipe program stdout: `received: hello\n`; stderr empty; no prompt.
* PTY master output: `input> hello\r\nreceived: hello\r\n` normally. If scheduling
  lets the input echo precede the prompt, `hello\r\ninput> received: hello\r\n`
  is also admissible. Accept exactly those two raw byte strings, not arbitrary
  whitespace stripping. The terminal's existing ECHO/ONLCR configuration predicts
  the extra input echo and CRLF conversion. Their attribution is interpretation;
  the raw merged PTY bytes remain the observation.
* Both record exactly one prompt-sensitive program reply with unchanged content,
  actual input bytes equal to the request, exit code 0 and no exit signal.

Acceptance: complete verified standalone v2 receipts; definition equality except
attachment; exact raw-output predicates above; both workers end; all reported
relay/guardian/subject PIDs gone within 3 s; BEAM completes normally. One pair,
zero automatic retries, whole run <= 30 s. Preserve failures without normalization.

Claim boundary: an intentionally constructed terminal-sensitive interaction
changes when only its attachment changes. This tests the apparatus with a known
behavioral witness. It does not establish behavior of any unmodified application,
interactive timing sensitivity, controlling-terminal effects or an entire matrix.
