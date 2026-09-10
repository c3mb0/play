# receipt_001 — Phase D contract, before implementation

Question: can a standalone session journal identify what ran, retain what was
observed, and survive interruption as inspectable evidence without fabricating
completion? No new attachment axes or behavioral witness.

Receipt header v2 must carry run/session identity; executable and helper paths,
pre-spawn SHA-256 digests and helper-reported version; argv, exact environment
plus a documented language-neutral fingerprint, cwd; requested terminal/session
configuration; deadline and input-recording policy; OS/architecture/OTP versions;
and Erlang module identities. Observed topology, bytes, signals and exits remain
ordered events. Missing observations are unknown, never inferred from requests.
Pre-spawn file hashes are custody measurements, not exec-time attestation.

Recovery is an explicit offline snapshot operation into a new exclusive directory.
It copies the entire raw journal and existing seal bytes, if any, without altering
the source. It produces a checksummed interpretation: valid prefix length/events,
terminal status if actually recorded, trailing bytes, and first validation error.
An unclosed journal is incomplete, not successful/failed/exited. A malformed
complete line, bad sequence/identity, or mismatched checksum is quarantined.
No skipped records, replay, silent truncation, source rewrite or invented exit.
Snapshot completeness is separate from historical integrity and process liveness.

Pass criteria:

1. A normal OTP session yields a sealed standalone v2 journal with verifiable
   binary and environment fingerprints and recorded exit; no enclosing run needed.
2. Kill BEAM with SIGKILL after a SIGHUP-ignoring subject is ready and its journal
   is synced. The existing ownership chain reclaims reported processes in 3 s.
3. A fresh BEAM recovers the partial journal as incomplete/unknown, preserving
   byte count and SHA-256, with no synthesized terminal entry or source mutation.
4. Bounded fixtures distinguish torn final line, complete-but-unsealed journal,
   invalid middle line, skipped sequence, changed identity, post-terminal data,
   empty journal and wrong/malformed checksum. Never skip a corrupt line.
5. Reusing a recovery destination is rejected without changing any existing file.
6. Existing nine-session ownership gate still passes with the new receipt header.

EUnit fixtures are explicitly synthetic; the BEAM-kill case is a real local run.
Each external process wait <= 10 s, reclamation <= 3 s, whole experiment <= 60 s.
Zero automatic retries. Preserve failed attempts and all original gate evidence.
Power-loss durability, guardian kill, descendants and automatic replay are outside
this checkpoint. Recovery does not infer why a writer disappeared from bytes.
