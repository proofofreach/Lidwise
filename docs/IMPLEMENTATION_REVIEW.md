# Independent implementation review

Code amendments are **endorsed** after two substantive rounds and focused
ratification. Public launch still requires the real-device and distribution gates. Reviews ran in fresh contexts and could inspect the code. Claude Code
rejected access before work (`oauth_org_not_allowed`), so explicit native-model
fallbacks were used: Sol for Astra-authored lifecycle/build work; Astra for
Sol-authored core/UI work. No paid API fallback was enabled.

## Round 1: lifecycle/build (Sol)

| Finding | Adjudication | Amendment / evidence |
|---|---|---|
| Lock publication/reaping can split concurrent mutations | accepted-verified | Owner publication and recovery takeover are being corrected in core. |
| Missing optional policy invalidates ownership and permits unsafe removal | accepted-verified | Separate ownership evidence from policy validity; core regression required. |
| Stale legacy records can capture later external holds | accepted-verified | Locked off-state reconciliation and conservative legacy handling required. |
| Caller ARCHS can certify a thin archive as universal | accepted-verified | Verifier now unconditionally requires arm64 and x86_64; negative archive test added. |
| Legacy ipconfig grant not retired | accepted-verified | Upgrade/removal now inspect and retire the current account’s old grant. A customized or other-account global rule is retained with an explicit message; silently deleting another account’s grant is out of scope. |
| Native scanner missing from required inventory | accepted-verified | Installer and extracted verifier require it; negative tests added. |
| Extra executable outside app is ignored | accepted-verified | Expected package file inventory enforced; unexpected executable test added. |

Additional lifecycle tests cover copy failure, missing scanner, persistent bootstrap
failure with retained rollback backups, and external-hold removal. These are isolated
fixtures, not real launchd or hardware evidence. Actual app-instance/login behavior
still requires the real-device gate.

## Round 1: core/UI (Astra)

| Finding | Adjudication | Amendment / evidence |
|---|---|---|
| Frozen mutation prevents recovery; signal handler continues mutation | accepted-verified | Core is implementing bounded verified process-tree takeover and terminating signal handlers. |
| Abandoned ownership or caffeinate survives off state | accepted-verified | Reconcile off under the mutation lock before retiring claims/processes. |
| Malformed policy removes recovery authority | accepted-verified | Separate minimal ownership from valid policy; corrupted owned policy must fail toward restoration. |
| Historical permission and loaded job produce false recovery readiness | accepted-verified | Fresh session-bound guard/guardian health and failure invalidation added; noninteractive authorization proof is under review. |
| UI timeout excludes inherited pipe handles | accepted-verified | Atomic POSIX spawn process group plus nonblocking reads; one deadline covers exit and both streams. Tests verify elapsed time with inherited pipes and TERM-ignoring descendants. |
| Failed mutation retains obsolete off state | accepted-verified | Every command outcome now gets status reconciliation; valid observed phase is applied, unavailable verification becomes unknown. Tests cover failed activation, timeout and mismatched expected phase. |
| UI opens obsolete network log | accepted-verified | UI asks `netlog --path` for the effective path and no longer creates an empty legacy log. |

## Additional integration corrections

- Agent JSON status is cache-only; optional transcript scanning cannot delay power status.
- Native bounded JSONL parsing replaces hundreds of `plutil` launches and checks Codex child-session metadata.
- Normalize padded `wc` output so log trimming actually works on macOS.
- The next-session duration has its own optional JSON field; changing it does not change an active deadline.
- A dynamic AppKit probe confirmed long faults needed 394 points while the old menu frame remained 215. The same hosting view now resizes on model changes; grow/shrink and accessibility-press tests pass.
- Source input manifests are compared before and after compilation, then against the extracted candidate.
- The user explicitly selected a free GitHub community release. Developer ID signing/notarization is optional; safety and hardware gates remain required.

## Round 2 and package ratification (Sol)

Universal architecture enforcement, legacy permission cleanup, required scanner,
UI process deadlines, failed-command reconciliation, next-session duration,
dynamic menu sizing/accessibility actions and the effective log path were retired.
Two remaining archive defects were fixed: hidden root siblings are rejected, and
rejected packages preserve the previous ZIP/checksum. Dedicated negative tests
pass. Ratification verdict: **ENDORSED** for these amendments. The two final file
renames can briefly produce a mismatched pair if interrupted; checksum validation
fails closed.

## Round 2: core (Astra)

Verdict: **NO-SHIP**, with abandoned/off-state ownership retired. Three concrete
amendments remain accepted-verified:

- Process takeover must distinguish permission-denied liveness from a process
  that exited. A privileged writer cannot be omitted from quiescence checks.
- Both safety loops must restore on invalid owned policy, including a numeric
  deadline beyond the recorded duration and invalid battery policy.
- Every automatic restoration failure, including failure to acquire the lock,
  must invalidate session-bound readiness.

Ratification verdict: **ENDORSED** for all three amendments. Identity now uses
`ps` start identity; a live descendant that refuses STOP prevents takeover before
root termination. Both loops restore invalid modern policy. Automatic wrappers
invalidate session-bound verification on every failure and check session identity.
Focused regressions passed, including a surviving protected descendant with FD9
closed, excessive numeric deadline, invalid battery floor and failed lock recovery.
The reviewer also ran in-memory wrapper/session-isolation probes successfully.

Frozen core SHA-256 prefixes: `99589c8f2f1d` (CLI), `9d921ddbb3c4` (session module),
`9979817f3b5f` (core test), `b05d73c8963d` (safety test).

## Local integration evidence

`./scripts/check.sh` passed on September 15, 2026: all regression suites, universal
build, extracted archive validation and malformed archive rejection tests. A stale
observer fixture was corrected to expect unknown for incomplete session evidence;
its assertions that observation preserves session files remain intact.

## Remaining evidence

The real-device matrix, quarantined download validation and publication remain pending. The original daily-use installation has not been replaced. No release has
been published. See [hardware record](HARDWARE_VALIDATION.md) and
[release gates](../RELEASE_CHECKLIST.md).

## Codex Desktop follow-up

Local testing found an active Desktop task mislabeled finished. Its current
`response_item` activity did not clear a prior `task_complete` marker. The parser
now recognizes Desktop reasoning, calls, outputs and user/assistant messages;
system messages and metadata do not revive completed turns. A later explicit
completion remains authoritative. Child exclusion is unchanged.

The regression failed before the fix and passed afterward. The native parser,
discovery suite and full `scripts/check.sh` pass. Independent Sol review of the
Astra-authored patch: **ship**, no findings. The installed power-tested candidate
remains identifiable by its original revision; this follow-up changes only parser
behavior and its tests, plus release documentation.
