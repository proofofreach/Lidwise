# Session improvements implementation

Scope authorized September 15, 2026: the five priority additions in COMPARISON.md,
implemented concurrently. Preserve the manual session model, six-hour total cap,
native panel identity and free community distribution. No release publication,
daily-use installation, live power changes or real hook configuration edits are
part of development verification.

## Model selection

The model-selection skill was read at its canonical Claude path. Claude Fable was
attempted through the installed, authenticated CLI; it returned HTTP 403 because
the organization disabled subscription access. No API fallback was enabled.
Explicit fallbacks: Sol/high for session correctness and native UI integration;
Terra/high for the bounded agent integration work; fresh independent review after
integration. The coordinator owns the native verification probe, packaging,
documentation and integration checks. UI Suite applies as an extension of the
existing surface, not a redesign.

## File ownership

- Session agent: bin/lidwise, lib/lidwise/session.sh, optional history module,
  tests/test-lidwise-core.sh and new session feature tests.
- Activity agent: src/AgentScan.swift, bin/lidwise-agent-scan,
  lib/lidwise/observation.sh, new hook resources and agent tests.
- UI agent: src/Lidwise.swift, src/LidwiseUIModel.swift, new feature UI
  files, native UI tests, DESIGN.md.
- Coordinator: native probe sources and tests, build/package/install scripts,
  product and user documentation, final integration.

Do not edit another owner's file without coordination. All tests must isolate
runtime/state and stub power/privilege changes. Do not erase existing user edits.

## Session and JSON contract

- New command: `extend --by SECONDS`, serialized with other mutations. Only extend
  a currently owned, unexpired session; never exceed original start + 21600.
  Reject an over-cap request without mutation. Repeated `on` remains idempotent.
- Warn once when an owned session enters its last five minutes. Warning remains
  independent of optional activity settings; no warning for already expired state.
  A successful explicit extension can rearm a warning for its new deadline.
- `config set battery-floor PERCENT` accepts 1–100, default 20.
  `config set require-ac on|off` defaults off. Both apply to the NEXT session.
  Persist each session's actual policy and enforce it at activation and runtime.
- Additive status v1 fields: `default_battery_floor`, `require_ac`,
  `default_require_ac`, `can_extend`, `last_session` (object or null).
  `battery_floor` and `require_ac` describe an owned session's actual policy;
  defaults describe future sessions. Old clients may ignore the new fields.
- `last_session` fields: `session_id`, `started_at`, `ended_at`, `deadline`,
  `reason`, `restoration` (verified|failed|unknown), `battery_start`, `battery_end`,
  `power_start`, `power_end`. Missing measurements are null. Bounded private
  history has at most 20 entries; no transcript or job labels. Keep a session's
  failed restoration record recoverable and update it on later verified recovery.
- New `history [--json]` command; JSON `{schema_version:1,sessions:[...]}` with
  newest first. The last-session object is the newest history record. Malformed
  history must never delay or prevent sleep restoration.

## Agent contract

- Preserve working/quiet/finished fields. Add optional counts `waiting` and
  `failed` under each provider. Old payloads decode these as zero.
- Explicit events may report working, waiting, finished or failed. Unknown,
  stale, malformed or ambiguous input must not become a completed job. Bound
  event input, private storage, freshness and record counts.
- New CLI `hooks ...` delegates to `lidwise-agent-scan --hooks ...`.
  Support an explicit, reversible Claude/Codex adapter setup where the locally
  installed tool supports the event. Do not claim Codex waiting coverage without
  a supported signal. Show setup status and a dry-run/configuration preview;
  preserve unrelated user hooks. Never configure the actual user's tools in tests.
- Hook signals are observation only and must never mutate the power session.

## Verification probe contract

- New CLI `verify --expect awake|sleep --seconds N [--json]`, N 15–120,
  default 60. It delegates to the bundled native lidwise-lid-probe helper.
- The probe only measures. It never starts/stops a session or changes power,
  network, privileges, or hooks. Reads lid state and continuous versus awake
  monotonic time to report observed sleep, with a bounded sampling interval.
- JSON includes schema_version, expectation, result (passed|failed|inconclusive),
  summary, duration_seconds, closed_lid_seconds, sleep_seconds, max_sample_gap,
  model, os_version. Insufficient closed-lid evidence is inconclusive.
- UI offers a guided test from diagnostics, instructions to close/reopen the lid
  on a ventilated surface, progress and a copyable result. It uses a separate
  bounded worker so normal controls remain usable. No automatic fault injection.

## UI integration

Keep the collapsed menu compact. Show Add 30 minutes only for an extendable owned
session, expose next-session power settings behind Settings, and present the last
session in a readable detail view. Expose optional integration setup/status and
attention counts without inferring job success. Use existing serialized mutations,
timeouts, readback and stale-response guards. Explain unavailable capability.

## Completion evidence

Implementation and review results will be appended here. Existing hardware and
clean-download release gates remain separate and must not be marked passed by
fixture tests or local compilation.

### Integration decisions

- Terra's first activity adapter did not meet the runtime and configuration
  preservation requirements. Sol took over that bounded subtask. The native
  implementation removes the proposed `jq` runtime dependency, serializes event
  writes, and preserves unrelated hooks within a shared matcher group.
- Automatic setup targets Claude Code. Codex's single `notify` callback has no
  waiting signal; this revision preserves that configuration and keeps existing
  local-log completion observation. The UI reports the setup limitation.
- The app's fixed “Add 30 minutes” action needs room for the full 1,800 seconds.
  The generic CLI `can_extend` field only establishes that some extension fits.
  The UI therefore checks the actual start/deadline and full increment.
- A probe process timeout or nonzero exit invalidates any partial JSON output.
  A sleep result also needs sleep measured in an interval that began closed;
  unrelated sleep elsewhere in a test is inconclusive.
- The installer requires the new history module and native probe. The uninstaller
  removes this release's owned hooks before deleting their executable and retains
  the app/recovery setup on a cleanup failure. Older releases without history
  predate this hook adapter.

### Focused verification

- Core, session feature and safety suites passed using isolated power stubs.
  They cover concurrent extensions, the six-hour cap, warning rearming,
  next-session policy, zero-percent battery measurements, failed-to-verified
  history updates, bounded/corrupt history, and helper dispatch.
- Native probe fixtures and the compiled IOKit entry point passed. The test checks
  the clamshell notification constant against the actual macOS SDK. The live
  open-lid result is documented in HARDWARE_VALIDATION.md.
- Installer lifecycle fixtures passed, including missing history/helper rejection,
  hook-removal failure preservation, rollback and rename migration. No installed
  daily-use app, real hook configuration, or power settings changed in these tests.

### Independent review

Fresh Sol/high reviews the Astra-authored probe and packaging. Fresh reviewers
will inspect core, UI and activity after their implementation files freeze.
Claude remains unavailable due to the verified organization subscription block;
the model-selection standing override authorizes the explicit GPT fallbacks.

Probe/package review, round 1: **ship with changes**. Coordinator verified each
finding against the source and accepted all five:

1. **accepted-verified:** the renamed README hero was copied into the package but
   absent from the archive allowlist/comparison. Added it to both.
2. **accepted-verified:** awake classification could blame sleep before lid
   closure. It now fails only on correlated closed-lid sleep; unlinked sleep is
   inconclusive. Added the reported synthetic regression; probe tests pass.
3. **accepted-verified:** counting native binaries did not prove their locations.
   Verification now requires the exact four executable Mach-O paths and rejects
   extra native code. Added shell-substitution and misplaced-code archive cases.
4. **accepted-verified:** CLI usage required an expectation but parsing defaulted
   it. `--expect` is now required; the 60-second duration default remains.
5. **accepted-verified:** packaging docs described three executables. They now
   describe four and name the probe. The new archive gate stays pending until the
   final artifact is actually verified.

The reviewer passed probe fixtures, both architecture typechecks, lifecycle and
session-feature tests. Earlier files in `dist/` were stale; final packaging must
rebuild from this revision.

Probe/package round 2: **ENDORSED**, all five findings retired; both architecture
typechecks and the updated probe suite passed. Extracted archive verification
remains an integration gate.

Core/UI round 1: **ship with changes**, one P2 finding. **accepted-verified:**
history readers/upsert count valid records but can examine all late-invalid rows
under the byte limit. The reviewer measured 8.36 seconds for 1,800 invalid rows
in a 54 KB private file, exceeding the five-second status timeout and delaying
process retirement after restoration. The session author is adding a total-row
scan limit and regression coverage. The reviewer passed the session/UI suites and
inspected all six rendered fixtures with no visual blocker.

Core/UI round 2: **ENDORSED**. All four history paths now inspect at most 40 raw
rows before parsing. The same malformed fixture took 0.219 seconds. Regression
coverage includes a valid row beyond the scan boundary and verified mocked
restoration after dense invalid history.

Activity round 1: **ship with changes**, four findings accepted after coordinator
source verification and checking the official Claude hook reference:

1. **accepted-verified:** missing registry arrays were treated as empty. Finished
   requires both correctly typed arrays to be present and empty.
2. **accepted-verified:** stored hook state overrode later meaningful transcript
   work until expiry. The parser needs a meaningful event timestamp so real
   forward progress clears older attention/terminal state while metadata does not.
3. **accepted-verified:** ingestion errors became exit 2, which can reject a Claude
   prompt or request continuation after Stop. The installed observation hook must
   return success without decisions when ingestion fails; configuration commands
   must continue to report errors.
4. **accepted-verified:** deduplication suppressed events whose transcript existed
   but was outside the scan budget, and could add a synthetic quiet session beside
   explicit sessions. Deduplicate actual emitted sessions and add the connected
   fallback only after both evidence sources produce no sessions.

The initial integrated run passed application tests, built all four universal
executables, and verified its development archive. Its new shell-substitution
negative fixture failed while signing the intentionally invalid bundle: the shell
stub itself also needed a signature before the containing app could be signed.
The fixture now signs that stub, and native-path validation runs before signature
validation. All signature checks remain required. The full check must rerun after
the activity amendments and this fixture correction.

Activity round 2: **ENDORSED**, all four findings retired. Additional checks
corrected fractional ISO timestamps and early callback validation failures. Since
hook timestamps have whole-second precision, transcript updates within that same
second remain ambiguous; only a later second supersedes the stored signal. The
reviewer passed the final hook/parser suites and the discovery/cache suites.

All implementation review blockers are retired. The full local check passed on
September 15, including universal compilation, extracted development archive
verification, hidden/extra code, missing-helper, shell-substitution, thin-binary,
stale-guide and atomic-package rejection tests. The resulting candidate also
passed `verify-release.sh community` with four universal native executables.
Local check output is retained in `.build/feature-check-final.log`.

Final packaging includes these verification notes. No daily-use installation,
real hook setup, release publication, or disruptive power test was performed.
The only live new probe run was the documented open-lid measurement. Remaining
hardware, clean-download and live accessibility release gates stay pending.
