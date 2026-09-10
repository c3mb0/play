# Things I would want as the operator

A take-home note from the playground, not a rollout plan. The useful dream is an
execution interface that helps an operator check its own assumptions before the
next action. This round built six small exhibits, not a debugger or approval engine.

**Observed:** six cases passed in 4.850 seconds, one run, zero retries. Thirteen
intervention requests have separate response records. Six session journals are
sealed and verified. All twenty known OS PIDs were absent at the end; the Python
watchdog needed no emergency action. The exhibit itself explicitly cleaned up
the two intentional descriptor holders; that is not harness containment.

[Run](receipts/operator-20260910T213632Z/manifest.json) ·
[Interpretations](receipts/operator-20260910T213632Z/report.json) ·
[Interventions](receipts/operator-20260910T213632Z/interventions.jsonl) ·
[Independent cleanup](receipts/operator-20260910T213632Z/independent-cleanup.json).

## Five operator questions

| Question | Available evidence / exhibit | Smallest useful interface to take home | Rank |
| --- | --- | --- | --- |
| What did the process actually inherit? | Existing launch receipts bind executable, environment, cwd and requested topology; [width receipts](receipts/width-20260910T212259Z/pairs/report.json) include native pre-spawn settings and process IDs. No full inherited-descriptor inventory. | A read-only snapshot with collection time, descriptor identities, session/group membership, requested versus observed state, and explicit unavailable fields. | Small extension for snapshot; existing launch evidence available now |
| Why hasn't this finished? | input_wait and blocked_output both show a sleeping subject. stopped has external T state. held_output shows an absent parent and live holder while child_exit is still unavailable. | Separate child status, stream state and last progress. Return unknown with alternatives when evidence cannot distinguish waits. Emit child exit independently of stream EOF. | Small extension for lifecycle events; general wait diagnosis needs different machinery |
| Which bounded action can I take? | Successful write, pipe EOF, late-write rejection and termination are exercised. Request, return value, child exit and process absence are separate facts. | Exact session identity, operation/payload, observed preconditions, deadline, response and effect references. Preserve rejected/stale requests. | Available now as an experiment receipt; small extension for a reusable interface |
| What survived cancellation? | caller_death leaves worker/child alive until the OTP deadline. worker_death_descendant reclaims the direct chain but leaves a holder alive. | An explicit caller-lifetime policy and cleanup scope, followed by survivor observations. Stronger descendant containment must name its OS mechanism. | Small extension for policy; broader containment needs different machinery |
| Can I rehearse the failure? | Six disposable fixtures, bounded waits, deliberate STOP/CONT, caller/worker death, descriptor retention and independent holder cleanup. | One reproducible command with predeclared expectations and preserved evidence. | Available now: make operator-check |

## The two most useful surprises

**A dead child can look unfinished.** In held_output, the OS reported the parent
absent and the holder reparented to PID 1. The API had not delivered child_exit.
After we terminated the holder, output closed and the zero exit arrived. The
helper currently gates that event on all reader streams closing. An operator
would benefit from two independent facts: child exited, streams still open.

**Killing the caller does not kill the session.** The caller consumes events;
the session_worker owns the Port. Killing the caller left both worker and subject
alive in our sample; the existing 1200 ms OTP deadline subsequently cleaned them
up. Killing the worker reclaimed the direct process chain, but its descendant
survived. Neither result is an error in this harness's stated contract. Both are
bad surprises if a future operator assumes “cancel” has one universal meaning.

First wishlist choices: separate exit from EOF, then make caller lifetime policy
explicit. Neither change has been implemented in this round.

## An intervention receipt worth keeping

The exhibit's append-only interventions.jsonl records requests before performing
them, with action ID, full session identity, receipt path, operation, target,
observed worker liveness, timestamp and a declared 3000 ms ceiling. OS utility
calls have a stricter one-second bound; existing API command calls have their own
bounded waits. The ceiling is an experiment declaration, not a new enforcement API.

A response records the actual return value. Later evidence records application
output, child exit and independent absence checks. Examples:

- write returned ok; input_written and the application's hello output followed.
- late write returned session_closed; the rejection is retained outside the
  already-sealed session journal, which remains unchanged.
- terminate returned ok; the receipt later recorded signal 9; OS absence was
  checked independently.

A future interface could package those facts under one action ID. Its observed
preconditions must not masquerade as an atomic compare-and-swap or an approval.
Approval systems could refer to this concrete action description later; none is
built here. STOP/CONT and holder cleanup in these exhibits use explicit external
OS commands, not imaginary capabilities of the public session API.

## Keep the unknowns

The no-input cat and the undrained writer both appeared as sleeping processes.
A ps state or a silent transcript does not establish the current blocked syscall.
The backpressure explanation is supported by controlled guardian stop/resume,
cooperative before/after markers and complete output after resumption. Its
alternatives remain explicit; there is no universal wait classifier here.

Descriptor retention follows the cooperative fixture construction plus the
observed parent/holder/EOF sequence, not a generic descriptor inspection tool.
Snapshots are samples, PID/path checks are not stable kernel process handles,
and readback is setup-time rather than continuous. The emergency cleanup path
was prepared but not exercised in this successful run. Only the recorded known
PIDs are covered, not an arbitrary process tree.

MIT throughout our code; existing third-party notices retain their terms.
The workshop is complete. These are useful options for the future operator,
with no obligation to build them now.
