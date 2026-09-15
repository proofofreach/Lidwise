# Launch implementation evidence

Working record for the 1.2 candidate. **Public launch remains pending verification.**

| Area | Implementation and evidence |
|---|---|
| Session safety | Transactional ownership, kernel mutation lock, bounded recovery takeover, conservative incomplete-state handling, session-bound health evidence and versioned JSON. Focused core and safety suites passed; final amendments independently endorsed. |
| Native UI | Typed state, bounded command execution, reconciliation after failures, next-session duration, settings, and dynamic menu sizing. Model, inherited-pipe timeout, layout and accessibility-action tests passed. |
| Network preservation | Automatic DHCP/radio mutations removed. Read-only observation loop, bounded private logs and atomic private cache pass isolated regression tests. |
| Agent activity | Cache-only machine status; bounded native JSONL parsing distinguishes quiet activity from explicit completion and excludes child sessions. A separate coalesced UI worker refreshes activity while awake mode is off; stale callbacks cannot supersede a power mutation. Parser, observer and UI worker tests passed. |
| Lifecycle | Staged install, authorization before mutation, shared lock, rollback with retained backup on rollback failure, required helpers and conservative removal. Isolated lifecycle tests passed; real launchd behavior pending. |
| Build/archive | Universal app and two native helpers, inside-out signing, source manifests and extracted archive validation. Negative tests cover hidden/extra files, missing scanner, thin executable and stale documentation. Full local check, universal build and all negative archive tests passed. |
| Documentation | Shorter README; separate CLI, network, troubleshooting and competitor guides; explicit community distribution and hardware gates. |
| Security reporting | GitHub private vulnerability reporting verified enabled, September 15, 2026. |

## Outstanding release gates

Independent implementation review and ratification are complete. The full local check passed after the final core fixes. Real-device
validation, quarantined community-download testing, and release publication remain
pending. Developer ID signing/notarization is optional: the user selected the free,
non-notarized GitHub release route. The user authorized local installation and supervised testing. AC/battery lid
operation, normal lid sleep after off, timer restoration and guard-crash recovery
now have evidence in `HARDWARE_VALIDATION.md`. Remaining matrix cases and publication
are still pending.

## Scope

Release 1 safety fixes and Release 2 daily-use improvements from the launch review
are implemented for verification. Scheduled wake, agent-owned sleep, fan control,
remote displays and a general trigger engine remain explicitly deferred.
Authenticated-helper migration, signed automatic updates, lifecycle adapters and
event-driven observation also remain later work.

## Review availability

Claude Code returned `oauth_org_not_allowed` before work because organization
subscription access is disabled. Explicit GPT fallbacks implemented and reviewed
the changes. No paid API fallback was enabled. See
[the independent review record](IMPLEMENTATION_REVIEW.md).

## Completion audit

The original launch blockers map to the independent review and test evidence:

1. State/results: typed command results, serialized mutations, status reconciliation,
   bounded process/pipe lifetime and stale-response tests pass.
2. Ownership: idempotence, kernel serialization, malformed policy, incomplete
   activation, failed restoration and external-hold preservation tests pass.
3. Runtime/process safety: private atomic files, identity checks and protected-child
   takeover tests pass. Actual timer and guard-crash restoration passed; remaining recovery cases are listed in the hardware record.
4. Network: configuration-changing repair was removed because no safe supported
   renewal operation was established; full read-only loop tests pass.
5. Lifecycle: isolated install/rollback/removal tests and nested universal signature
   verification pass. Real launchd/login, manual instances and clean-device install
   remain unverified.
6. Release reconciliation: the source is committed and the local community candidate
   is rebuilt from that revision. A public tag and release remain pending hardware
   evidence; public latest is not claimed to contain these changes.

Daily-use improvements and documentation are implemented. Live menu keyboard,
VoiceOver and accessibility settings still require the real-device pass. Optional
notarization is superseded for this candidate by the user's free community choice.
The user subsequently authorized local installation and supervised testing; the
record distinguishes completed cases from remaining disruptive tests.
