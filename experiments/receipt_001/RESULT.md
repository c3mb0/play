# receipt_001 result

Observed PASS: `receipts/receipt-20260910T202559Z`, about 4.94 seconds total,
14 recorded checks, zero automatic retries. Implementation committed as `b4883b8`
before execution; helper version 0.3.0 on macOS arm64 / OTP 29.0.6.

* Normal session: self-contained v2 header; binary SHA-256 and language-neutral
  environment fingerprint independently verified in Python; actual child exit
  present; seal verified by a fresh Erlang VM.
* Detached journal + checksum: validated without the enclosing run manifest.
* Real BEAM SIGKILL: exit status -9 after readiness and journal sync; relay,
  guardian and SIGHUP-ignoring subject all absent within three seconds.
* Fresh-VM recovery: original interrupted bytes/hash unchanged, no source seal
  fabricated, no terminal event appended; classification incomplete, outcome
  unknown. This is recovery of evidence, not continuation of the session.
* Synthetic empty/torn-tail/unsealed-complete cases classified distinctly.
* Synthetic malformed middle line, sequence gap, identity change, post-terminal
  bytes, environment-fingerprint mismatch and bad/malformed seals quarantined.
* Reused recovery destination rejected; every existing destination hash unchanged.

All seven EUnit tests passed, covering decoder boundaries, recovery edge cases
and unambiguous environment encoding. Rust tests, build, formatting, Clippy,
Erlang compile with warnings as errors, xref and Python syntax checks passed.
Named xref exemptions cover external experiment/API and supervisor entrypoints.

Regression: all nine prior ownership cells passed with the new writer/header in
`receipts/ownership-20260910T202628Z`. The original probe binary hash is unchanged.
No failed runtime receipt attempt occurred in this checkpoint; compile-time xref
warnings for the exported inspection API were resolved before the experiment.

Limits: runtime reclamation after this BEAM-kill condition is observed on this
Mac. Guardian-kill/descendants are not contained by this result. Recovery does not
infer exit status from missing data, restore a crashed writer process, or establish
power-loss durability. Pre-spawn hashes are not exec-time attestation.
