# Final competitor analysis

Checked September 15, 2026. This replaces the earlier launch-review snapshot.

## Recommendation

Position Lidwise as **predictable closed-lid sessions for long local work**.
Make it easy to start a bounded session, understand its limits, and verify that
normal sleep is allowed again.

The current product has a credible foundation, but this review found **no established
exclusive feature advantage**. Closed-lid operation, free source, timers, battery
limits, thermal checks, crash restoration, and agent awareness all exist elsewhere.
Manual operation is useful for mixed workloads and long pauses, but competitors
also offer manual sessions. Simplicity and reliability must be demonstrated through
the whole experience, not claimed from a shorter feature list.

Prioritize release verification, easier installation, session-end controls, readable
session history, editable power policy, and better activity signals. A large trigger
engine would make the product harder to distinguish.

## Scope and evidence

- Our baseline is the local 1.2.0 candidate at source revision
  `79f33b524823bc1f7060d096d6a1487c4f8f96b9`, plus the current README and hardware
  record. This is implemented candidate functionality, not a public-release claim.
  The latest public download remains
  [v1.0.0](https://github.com/proofofreach/Lidwise/releases/tag/v1.0.0).
- Our claims were checked against the CLI, session policy, observer, native UI,
  installer documentation, and [hardware evidence](HARDWARE_VALIDATION.md).
- Competitor capabilities below are primary-source documentation claims. Release
  metadata was checked for the main open-source alternatives. Their apps were not
  installed or tested, and signatures were not independently validated.
- Current README features can be ahead of downloadable releases. Release assets
  establish availability, not that every current documentation claim ships in them.
  “Not documented” means support was not established, not that it is absent.
- Prices are displayed offers on the review date. This is a bounded search, not a
  market census or evidence of demand, retention, or market share.

## Our feature set against the market

| Capability | Lidwise 1.2 candidate | Assessment |
|---|---|---|
| Closed lid without an external display | Local AC and battery evidence on one Apple Silicon Mac; broader execution coverage pending | Essential capability; several direct alternatives document it |
| Manual session and timer | Shared GUI/CLI session; GUI presets 30m, 1h, 2h, 6h; CLI durations up to 6h; repeated `on` preserves the deadline | Good foundation; others also offer manual sessions and more time controls |
| Battery and heat limits | Default 20% battery floor; critical or sustained high thermal pressure ends the hold | Expected protection; no normal saved GUI floor control or charging-only setting |
| Crash restoration | Separate guard and guardian; restoration readback; local guard-crash test passed | Valuable, but watchdogs and restoration are also documented elsewhere |
| Ownership and status | Owned, external, unknown, pending and fault states; versioned JSON; setup diagnostics | Strong foundation; no perfect ownership exists for the global OS flag |
| Agent activity | Claude Code and Codex; working/quiet estimates; finished requires an explicit event | Narrower coverage than several rivals; no dedicated “needs your attention” state |
| Other local work | Goal registration, PID/activity-file observation, completion/failure commands | Useful for mixed workloads; requires manual integration; goals do not control sleep |
| Notifications | Local events; opt-in agent alerts; optional `VIBECAF_NTFY_URL` forwarding | Already present; missing advance expiry warning and normal remote-notification setup |
| Network visibility | Optional read-only diagnosis and bounded logs | Supporting context; not unique and not automatic Wi-Fi repair |
| Daily controls | Shortcut, login controls, copyable diagnostics, About, support and release links | Already implemented; do not put these on a missing-features list |
| Session history | Current state and diagnostic logs | No dedicated history explaining the last session's end and restoration result |
| Installation and updates | Free ad hoc signed ZIP, shell installer, administrator setup, Open Anyway where required; update link opens GitHub | Adoption gap against easier installs and signed update channels |

Our implementation references: [CLI](CLI.md), [network behavior](NETWORK.md),
[security model](../SECURITY.md), [accepted design](../DESIGN.md),
[implementation status](IMPLEMENTATION_STATUS.md), and
[hardware evidence](HARDWARE_VALIDATION.md).

### Implementation update

The five ranked additions below are now implemented in local source after this
baseline comparison. They are not a published release or new hardware certification.

| Addition | Current implementation |
|---|---|
| Session endings | Final-five-minute warning; explicit CLI extension and cap-aware “Add 30 minutes” action |
| Power choices | Saved battery floor and AC-only requirement for the next session |
| History | Up to 20 private records with end reason, power context, and restoration result |
| Agent attention | Reversible Claude lifecycle setup; waiting and failure states; Codex retains log completion with no waiting adapter |
| Local verification | Guided native lid/clock measurement with copyable passed, failed, or inconclusive result |

The remaining strategic priorities are release evidence and installation quality.
These additions improve the complete session experience; they do not establish an
exclusive feature advantage. See [implementation and review evidence](FEATURE_IMPLEMENTATION.md).

## Competitors that matter

| Competitor | Price/model | Relevant documented strengths | Implication for us |
|---|---|---|---|
| [Keepresso](https://github.com/gyorgysh/keepresso) | Free, GPL-3.0 | Manual/custom timers, expiry warnings, broad agent hooks, bounded automation leases, scheduled wake, battery/thermal controls, assertion viewer and history, diagnostics, native helper, Shortcuts and updates | Closest broad competitor. Feature count is an unattractive contest; recovery and explainability also overlap |
| [Lidless](https://github.com/nghialuong/Lidless) | Free, MIT | Compact manual control; XPC helper/watchdog; battery, charging, thermal and timer policies; notarized DMGs and Sparkle documented | Focused utility and installation benchmark. Current README does not establish agent lifecycle integration |
| [Nemuri](https://nemuri.app/) | Free basic; Pro $19 once | Free battery guard/watchdog; paid per-project agent states, attention alerts, hooks and automatic release | Waiting-for-user feedback is valuable. Its free tier competes with our manual core |
| [Hold My Lid](https://holdmylid.app/) | $9.99 early offer; $14.99 regular, once, up to 3 Macs | Lifecycle hooks, multiple providers, charging/battery policies, display controls, quick pause and Homebrew | Agent coverage/setup benchmark. Closed-lid assertion claim not independently verified here; provider descriptions differ between sections |
| [Let It Brew](https://letitbrew.app/) | Free, Apache-2.0 | Claude Code, Codex, OpenCode and Copilot; multiple sessions; battery/AC/display controls; update checks | “Free and built for agents” is occupied. It documents releasing the hold when agents wait for input, a policy users may not want |
| [goguma](https://github.com/junnam586/goguma) | Open source, MIT | Scheduled wake, command-scoped holds, agent integrations, leased recovery, job history and learned run windows; menu app plus CLI | Benchmark for command lifetimes and future scheduled work. Its app is also a viewer for an independent service |
| [Perked](https://tryperked.app/) | Displayed €1 launch tier; planned €5/€9 tiers, once | Agent/app detection, manual timers, battery/thermal policies, event journal, Lock & Leave, notarization documented | Small native UI, local operation and low price are not sufficient differentiators |
| [LidAwake — NeoSpecies](https://github.com/NeoSpecies/LidAwake/blob/main/README.en.md) | Open source, MIT | Published lid-close probe, CLI/JSON, battery/thermal/time policy, event-driven monitoring, idle-exit design | Evidence/performance benchmark. Docs disclose unsigned packaging; latest release has no attached binary assets |
| [Lid Awake — thuongtin](https://github.com/thuongtin/lid-awake) | Open source, MIT | Approved helper, power/display controls, optional lock on lid close, signed/notarized releases and Sparkle | Distribution and lock behavior benchmark. Public binaries are Apple Silicon only |
| [Decaf](https://github.com/grishahq/decaf) | Open source | Claude/Codex hooks, approval alerts, automatic sleep and optional Telegram summaries | Remote completion/attention messages already exist. Documented install is source-based and unnotarized |
| [Agent Awake](https://github.com/rk1000000/Agent-Awake) | Free, MIT | Timed/agent modes, authenticated heartbeat, optional thermal/energy controls, charging diagnostics | Agent parsing and heat checks also overlap. README limits verified hardware and identifies an ad hoc build and Russian UI |
| [LidSleepToggle](https://github.com/Sufxx/LidSleepToggle) | Public source | Work detection, adaptive idle handling, battery/thermal/charging policy and timers | Another direct example of the crowded automatic-work category |
| [Amphetamine](https://apps.apple.com/us/app/amphetamine/id937984704) | Free, App Store | Mature triggers, timers, app/download sessions, low-battery cutoff, scripting and Closed-Display Mode | Important incumbent. Do not claim it has no closed-lid feature; its release notes describe Apple Silicon power-transition issues and supporting scripts |
| [Lungo](https://sindresorhus.com/lungo) / [KeepingYouAwake](https://github.com/newmarcel/KeepingYouAwake) | Lungo price not checked; KeepingYouAwake free/open source | Focused keep-awake interaction; Lungo has Shortcuts/URL automation | Adjacent simplicity benchmarks. Their own docs exclude our standalone battery-only closed-lid scenario |

Additional discovery included [KeepAwake](https://keepawakeapp.com/), which markets
virtual-display-based closed-lid operation. Its mechanism was not validated here
and was not scored as equivalent. Earlier discoveries remain leads in
[the launch review](LAUNCH_REVIEW.md#current-competitors); they are not evidence of
current support unless rechecked.

Release metadata confirmed downloadable assets for
[Keepresso v1.25.0](https://github.com/gyorgysh/keepresso/releases/tag/v1.25.0),
[Lidless v0.1.3](https://github.com/nghialuong/Lidless/releases/tag/v0.1.3),
[goguma v0.1.12](https://github.com/junnam586/goguma/releases/tag/v0.1.12), and
[thuongtin's Lid Awake v0.1.7](https://github.com/thuongtin/lid-awake/releases/tag/v0.1.7).
[NeoSpecies v1.1.0](https://github.com/NeoSpecies/LidAwake/releases/tag/v1.1.0)
had no attached assets. Keepresso's latest release explicitly verifies the off
state before “Turn off and quit” finishes; that behavior is not exclusive to us.

## How to differentiate

### 1. Serve people running several kinds of local work

The strongest fit is a developer with an agent, build, transfer or other process
running together, who wants one explicit work window. A quiet agent does not
necessarily mean the whole machine is ready to sleep. The chosen session remains
authoritative, subject to the deadline and protective cutoffs.

This is a product focus, not a unique mechanism. Someone who wants only automatic
agent completion is currently better served by an automatic alternative.
Our manual default also has a real cost: the Mac can remain awake after work ends,
or its deadline can arrive before the work finishes.

Suggested positioning:

> Keep your Mac awake for a session you control, with a clear deadline and visible
> sleep restoration.

Supporting proof should answer: Is closed-lid operation available here? When does
the session end? What else can end it? Did the app successfully release its hold?

### 2. Make the proof part of the product

Ship a reproducible “Test closed-lid operation” flow and a short session record.
Show the tested Mac/OS, observed result, end reason and restoration result. Make
diagnostics easy to export with sensitive job labels excluded by default.

A future record might say: “Session ended at 14:30: deadline reached. This app's
sleep override was cleared and verified.” It must not say “Mac slept” or “job
completed” without evidence for those separate events.

Published verification already exists in
[NeoSpecies' project](https://github.com/NeoSpecies/LidAwake/blob/main/README.en.md).
Our opportunity is to make that evidence accessible during everyday use and keep
it current across releases. It does not justify “the only safe app.”

### 3. Keep setup and everyday use small

One primary session control should remain sufficient. Put occasional settings and
optional activity behind disclosure, as the current design specifies. Improve
installation before expanding the panel. No account, transparent permissions and
free access support the choice, but are not unique selling points.

This is an execution advantage to earn. This review provides no head-to-head
failure-rate, installation-time, battery-drain or usability measurements proving
that we already win.

## Missing features and priority

These are recommendations, not approved implementation scope. They preserve the
manual default unless a later product decision explicitly changes it.

### Before public release: finish the promised product

**Complete the existing hardware and clean-download gates.** The public artifact
does not contain the candidate's safeguards. Finish the supported test matrix or
narrow support claims. Pending cases include logout/reboot, several failure paths,
clean installation/removal and live accessibility checks. See the
[hardware record](HARDWARE_VALIDATION.md) for the exact remaining cases.

Do not advertise precise-time sleep: the recorded timer test restored the flag
about 26 seconds after expiry; recorded guard-crash restoration took about 180
seconds. These are individual observations, not worst-case guarantees. Restoring
normal sleep policy is not proof of uninterrupted sleep.

**Reduce installation uncertainty.** Make progress, permission requests, successful
setup and removal understandable in the current free community route. An
authenticated native helper is a useful later investment: the current narrow
sudoers permission is available to any process running as the account, not only
our app. Migration needs its own review and testing.

Notarization would improve mainstream adoption, but the selected release route is
free and unnotarized. Do not silently change that budget decision. Homebrew can
improve developer installation after its install/upgrade/uninstall paths are
verified; it does not substitute for notarization.

### Next release: highest-value additions

Implementation of these five additions is tracked in
[FEATURE_IMPLEMENTATION.md](FEATURE_IMPLEMENTATION.md). This comparison records
the feature baseline at the time of the analysis; implementation is not public
release or hardware certification.

| Rank | Addition | Smallest useful version | Why it belongs |
|---|---|---|---|
| 1 | Expiry warning and explicit extension | Warn before expiry; offer “Add 30 minutes” with the new deadline. Keep the six-hour total cap from the original start; require a new session beyond it. Repeated `on` stays idempotent | Resolves a predictable failure of manually estimated work windows without making them indefinite |
| 2 | Last-session record | Start/end time, deadline, end reason, battery change with power context, and verified/unverified restoration. Keep a small bounded local history | Answers “why did it stop?” and makes recovery work visible |
| 3 | Saved battery policy and charging-only option | Persist the existing floor as a normal setting; add opt-in AC-only operation; specify active versus next-session effects | Expected control; users should not need environment variables |
| 4 | Explicit attention state | Optional Claude/Codex lifecycle adapters; per-session working, waiting, finished, failed or unknown only where supported; preserve existing hook configuration | More useful than many weak process detectors. Observation still does not decide sleep |
| 5 | Guided local verification | Reusable lid-close probe and recovery check with instructions and an exportable result | Supports the positioning and diagnoses machine-specific failures |

Expiry alerts need realistic delivery: a local banner may not be seen with the lid
closed. Optional forwarding can build on existing notifications; delivery must
not be assumed or become a recovery dependency.

An OS “Lock and start” action is a small useful follow-on. First verify screen
locking during our hold. Preventing sleep does not prove that the screen locked.
Competitors expose this convenience, including [Perked](https://tryperked.app/)
and [Lid Awake](https://github.com/thuongtin/lid-awake).

### Later: useful only with demonstrated demand

- **Explicit command-scoped mode.** Best larger expansion if users want automatic
  release. A wrapper can report actual exit status; an opt-in leased hold can end
  when all registered commands finish. Preserve separate manual sessions and other
  holds, expire after client failure, and obey battery/thermal/time policy.
  A quiet transcript must never stand in for exit. The goal registry is currently
  observation-only; this would be new behavior.
- **Shortcuts and URL actions.** Convenient ways to launch the same bounded session.
  CLI scripting already exists, so these are not launch blockers.
- **Update availability and verified installation.** The update command already
  opens the release page. Add version comparison and a trustworthy update path if
  manual upgrades become a support burden.
- **Broader agent coverage.** Follow actual requests after existing integrations
  distinguish attention from completion reliably.
- **Lower observation overhead.** Benchmark off/active CPU, wakeups and energy
  first. The shared observer is not proof of lower power use than a rival.

### Do not expand into these now

Scheduled wake, general trigger rules, virtual displays, remote desktop, fan
control, mouse activity simulation, cloud accounts and fleet management. Each
serves a different buying decision and adds maintenance. Automatic network
configuration changes should remain outside the current promise.

## Decision and validation

Ship the verified bounded-session utility. Then improve **session endings, power
choices and activity clarity** before adding an automatic work mode. Keep the
community edition free; this analysis establishes neither willingness to pay nor
a reason to add a subscription.

Validate the positioning with developers doing both single-agent and mixed local
work. Have them install a release, start a session, handle expiry, and explain a
stopped session. Compare task success, setup friction and understanding with one
focused competitor and one broad competitor. If they consistently want “sleep when
this command finishes,” prioritize explicit command mode over more manual controls.

The durable advantage would be trust earned through simpler operation, clear
failure explanations and repeatable hardware evidence. No single feature in this
review establishes that advantage by itself.
