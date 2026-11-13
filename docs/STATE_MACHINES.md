# Lidwise state machines

This file lists the explicit and implicit state machines in Lidwise. For each
one it gives the states, the invariants, and the transitions. It also records
the invalid states and transitions that the code could actually reach, and the
fix for each. Keep it current when a transition changes.

Sources: `bin/lidwise`, `lib/lidwise/session.sh`, `lib/lidwise/guardian.sh`,
`lib/lidwise/observation.sh`, `src/Lidwise.swift`, `src/LidwiseUIModel.swift`.

## 1. Power phase (derived, not stored)

`session_phase` derives the phase from `pmset -g` `SleepDisabled` and the
session record. Every command and every loop reads the phase again; nothing
caches it.

| SleepDisabled | Session record | Phase |
|---|---|---|
| unreadable | any | `unknown` |
| 0 | any | `off` (residue is cleaned by `turn_off`/guardian) |
| 1 | owned (modern `enabling`/`active`, or valid legacy) | `owned-on` |
| 1 | residue that cannot be classified | `unknown` |
| 1 | none | `external-on` |

Invariants:

- P1. Lidwise changes `SleepDisabled` only while it holds the session lock.
- P2. Lidwise never clears an `external-on` hold unless the user passes `off --force`.
- P3. `unknown` never changes power state.
- P5. Every process resolves the state folder the same way
  (`state_paths_resolve`). It uses `Lidwise` when that folder exists, or when
  no pre-rename `Closed-Lid Awake` folder exists. Otherwise it uses the old
  folder. Only the installer's maintenance window moves the old folder, with
  the lock held, sleep verified off and no session. The guardian re-resolves
  the path on every loop step, so it can never watch a folder the CLI no
  longer uses. Deleting the live folder while a session runs leaves an
  unowned sleep block (`external-on`); `off --force` clears it.
- P4. A non-private state directory is repaired when the user owns it. Otherwise
  it is treated as untrusted, and `on` refuses to start (`private_dirs_repair`,
  `private_dir_untrusted`).

## 2. Session record (persisted: `session/`)

States: `none` → `enabling` → `active` → `none`.

| From | Event | Guard | To | Side effects |
|---|---|---|---|---|
| none | `on` (lock held) | preflight passes | enabling | `session_claim` writes id, state, enabler identity first, then policy |
| enabling | `pmset 1` verified, caffeinate + guard started | `session_claim_current` | active | `recovery_verified_*`; guardian woken (file + doorbell) |
| enabling | any activation step fails | — | none (rollback) | `pmset 0`; history `activation failed` |
| enabling | rollback cannot restore sleep | — | enabling (orphaned) | recovery marked failed; guardian recovers it |
| enabling | enabler process dead (crash) | lock free or reclaimable | none | guardian: `session activation did not finish` |
| enabling | age ≥ `ACTIVATION_GRACE` or deadline passed | — | none | guardian: `session activation timed out` |
| active | `off` / `toggle` | — | none | `pmset 0`, history, processes retired |
| active | guard: deadline, thermal, battery floor, AC rule, invalid policy | lock held | none | notification `Awake mode turned off` |
| active | guard heartbeat older than `GUARDIAN_GRACE` | — | none | guardian: `guard heartbeat lost` |
| active | `on` again, session healthy | — | active | guard/observer restarted; deadline unchanged |
| active | `on` again, policy invalid or deadline passed | — | none → enabling | old session ended with that reason, new one created |
| active | `extend --by N` | timed, unexpired, total ≤ 6 h | active | new deadline; warning reset |
| any | `pmset 0` seen while owned | enabler not mid-activation | none | guardian `reconcile_off`: history `sleep was already restored` |

Invariants:

- S1. `state ∈ {enabling, active}` if and only if `id` is valid.
- S2. In `enabling`, `enabling_pid`/`enabling_start` identify the live process
  that holds the lock.
- S3. A timed session has `1 ≤ deadline − started_at ≤ 21600`. Full On has
  `duration_seconds = 0` and `deadline = 0`.
- S4. Only one recovery definition exists: `recovery_reason`. The guardian's
  observation and the lock reclaim both use it, and so does the re-check made
  under the lock.
- S5. The guardian acts only on a reason that still holds under the lock.

## 3. Owned processes (runtime records: `/tmp/vibecaf.UID/*.pid`)

Each record is `pid|role|session|lstart`. A record matches only when the pid,
the start time, and the role marker are all the same.

| Process | Starts | Ends |
|---|---|---|
| caffeinate | activation | session retirement |
| guard (`__guard`) | activation, or `on` for an existing session | retirement, `pmset 0`, **or its session id is no longer current** |
| observer (`__observation`) | activation, `config set recovery on` | retirement, **or its session id is no longer current** |
| lock contender | every locked command | lock release; killed only by a reclaim whose recovery is still due |

The guard sleeps `min(GUARD_EVERY, deadline − now)`, so it enforces the
deadline on time.

## 4. Guardian loop (LaunchDaemon, `__guardian`)

`check` → idle wait of up to `GUARDIAN_EVERY` seconds, in 1 s steps → `check`.
A `guardian_wake` file ends the wait early. The FIFO doorbell
(`guardian.doorbell`) ends a 1 s step at once. When the doorbell is missing or
its read fails without waiting, the loop falls back to `sleep 1`, so it can
never spin.

## 5. Menu bar app (in memory)

`state.phase` comes from the last accepted `status --json` result. `pending ∈
{nil, turningOn, turningOff, extending, saving}`. One `RevisionGate` drops
stale results. While `pending` is set, refreshes are deferred. After a
mutation, the app always reconciles with a fresh status result; it never uses
the old UI state as evidence. A readiness burst refreshes every 1 s for up to
40 s until `recovery_ready`. The card host resizes after the pending SwiftUI
update is applied.

## Defects found and fixed

| ID | Impact | Reachable by | Evidence | Fix | Test |
|---|---|---|---|---|---|
| SM-1 | High: false "Crash recovery failed", recovery marked failed, sleep stays blocked for up to 30 s | `on` killed after `pmset 1` (app timeout, crash) | the "did not finish" branch always failed the reclaim within grace | reclaim allowed when the enabler is dead (`recovery_reason`) | `test-state-machines.sh` SM-1 |
| SM-2 | High: healthy session marked unverified for its whole life, plus a false alert | guardian's periodic check during the ~0.5 s `enabling` window, or `off` during a check | unlocked observation acted on without re-check | `guardian_recover` re-evaluates `recovery_reason` under the lock; a no-op when it no longer holds | SM-2 (deterministic `ps` hook) |
| SM-3 | Medium: `on` reported "on", then the guard turned it off up to 60 s later | `on` on an expired or malformed active session | retained any active session | end and replace it | SM-3 |
| SM-4 | Low: orphan guard/observer that keeps taking the lock or probing the network; a guard that ended its own session lingered one more interval | retirement failure, record mismatch, external hold, any guard auto-off | loops ran until `pmset 0` or a kill | exit when the session id changes, checked before and after each guard check | SM-4, SM-5 |
| SM-5 | Low: deadline overran by up to `GUARD_EVERY` (60 s) | every timed session | fixed sleep interval | `guard_delay` | SM-5 |
| SM-6 | Medium (UI): new long fault clipped until the next update | any longer fault or expanded activity | host measured `fittingSize` before SwiftUI applied the change | force layout before measuring | `test-lidwise-ui.sh` (was failing) |
| LAT-1 | Activation latency about 2.2 s (mocks) | every `on` | guardian 1 s poll; 16 separate field writes; 3× `session_valid` in status | doorbell FIFO, `write_fields`, builtin `read`, one `stat` per check, status memo | activation-latency check (< 1.5 s) |
