# Lidwise: launch review

Date: 2026-09-15. Reviewed working tree at `acd5cdc`, including the existing uncommitted agent-scanner fix.

## Verdict

**Do not promote the current build as ready for unattended public use yet.** The normal path works and all existing checks pass. The remaining blockers concern truthful status, recovery ownership, network changes, and distribution. Daily use is useful evidence for one setup; it does not exercise failed authorization, concurrent commands, stale processes, or fresh installation.

The product should remain a **manual, time-bounded awake session with optional work monitoring**. The current separation between monitoring and sleep ownership is sound. However, competitors also offer manual sessions. This is a product focus to execute well, not an exclusive capability.

This review does not change the installed app, system sleep settings, networking, login items, or privileges. Production code remains unchanged. Findings below are a launch backlog, not completed fixes.

## Verified scope and results

- Read all 27 tracked files, including all source, scripts, tests, documentation, configuration, license, and the icon asset. Read both existing uncommitted changes.
- Inventoried generated `.build` and `dist` outputs separately. Inspected app metadata, executable architectures/signatures, all three ZIP inventories and checksums, and whether bundled helpers match current source. Generated artifacts are not independent source files.
- `./scripts/check.sh`: **PASS**. All seven shell suites pass; all three Swift sources typecheck; universal app and thermal helper build; bundle signature verification and plist validation pass.
- Build host: Apple Silicon, macOS 26.6.2. Intel binaries compile; Intel execution and macOS 13 behavior were not tested.
- Current local bundle: ad hoc signature. `spctl --assess --type execute --verbose=2` rejects it. One valid local code-signing identity exists; its suitability for Developer ID distribution and notarization credentials were not established.
- Rendered and inspected the existing collapsed and expanded `CARD_PREVIEW` views and a synthetic low-battery/network/guard-fault state. These are synthetic view renders, not a live NSMenu, keyboard, VoiceOver, or fresh-install test. The computer-use app inventory did not expose Lidwise.
- Ran additional isolated probes using the actual shell functions and actual Swift status parser with fake inputs. No real power/network writes occurred. Results appear below.
- Read current competitor documentation and public release metadata. Competitor features are documented claims unless explicitly stated otherwise; competitor apps were not installed or independently hardware-tested.

## Launch blockers

### 1. P1 — Show verified state and command failures

**Evidence:** `src/Lidwise.swift:14`, `:68`, `:450`, `:841`, `:886`.

The process wrapper discards the exit status and stderr. `toggle()` displays a success HUD based on the requested action, regardless of its outcome. Both an empty helper response and `AWAKE MODE: UNKNOWN` parse as `state.on == false`; the card then says closing the lid sleeps the Mac. The protection badge only tests a guard PID and whether a launchd label exists; it does not establish that sleep restoration is authorized or that thermal monitoring works.

**Failure:** deny authorization, remove the helper, or make `pmset -g` fail. The UI can announce success or normal sleep without evidence. Two quick clicks can also launch concurrent commands from the same stale state. Older refresh results can overwrite newer results.

**Fix:** return a typed command result with exit status, stderr, and timeout; represent `off`, `on`, `unknown`, and pending transitions separately. Serialize mutations, discard obsolete refresh responses, and display success only after verifying the resulting power state. Expose actionable recovery faults. Do not label an unverified session “Protected.”

**Acceptance:** missing executable, canceled authentication, failed on/off, unknown state, delayed status, and repeated toggles produce correct messages and no overlapping mutation.

### 2. P1 — Make session ownership transactional

**Evidence:** `bin/lidwise:210`, `:223`, `:234`, `:991`, `:1067`, `:1110`.

`on` has no already-on check or cross-process lock. It overwrites the ownership record before authorization and clears the session when authorization fails. Running `on` successfully again resets the six-hour deadline. A failed manual `off` stops the guard before attempting privileged sleep restoration.

Status also equates global `SleepDisabled == 1` with this app being on, even without its ownership record (`bin/lidwise:1190`, `:1238`). Both the UI and CLI toggle then call `off`, which clears the global flag. Another tool can own the hold, yet this app presents and removes it as its own session.

**Isolated results:** failed repeated `on` removed both `owned` and `active` from a preexisting session. Failed `off` killed the fake guard and removed its PID record while retaining ownership. The independent guardian can still recover the latter after its grace period if it is running and authorization becomes available; the former removes the guardian's authority to recover.

**Fix:** one cross-process session lock; idempotent `on`; explicit session ID and persisted policy/deadline; preserve existing ownership on errors. Distinguish `owned-on`, `external-on`, `off`, and `unknown` in the state model. Verify `SleepDisabled == 0` before retiring recovery processes. Validate policy inputs and avoid claiming another tool's existing global sleep block. Recheck immediately at startup, including battery, thermal state, and noninteractive restoration capability.

**Acceptance:** concurrent on/on, on/off, repeated on with lost authorization, failed off, interrupted activation, failed state writes, and helper crash leave either normal sleep or an owned session with working recovery. Repeated on does not extend the deadline. Another tool's hold remains unchanged unless the user explicitly chooses an override.

### 3. P1 — Validate process identity and protect every runtime file

**Evidence:** `bin/lidwise:26`, `:129`, `:445`, `:882`, `:1055`, `:1110`.

PID files are trusted after only `kill -0`. That checks whether some process exists, not whether this session started it. Predictable PID and network-state files are stored directly in `/tmp`; only the agent-cache directory has a symlink defense.

**Isolated result:** pointing the caffeinate PID file at a disposable, unrelated `sleep` process caused `off` to terminate that process. Stale/reused PIDs can also make start functions believe guards already exist. A forged network-state timestamp is consumed in shell arithmetic and deserves the same input validation as durable timestamps.

**Fix:** private per-user runtime directory, restrictive permissions and ownership checks, symlink-safe creation, and a session-bound process identity (PID plus start identity, or a supervised helper that owns its children). Never signal an unverified PID. Validate cached state as data before arithmetic.

**Acceptance:** reused PID, malformed PID/timestamp, precreated symlink, precreated foreign-owned directory, and stale files cannot kill unrelated work or suppress guard startup.

### 4. P1 — Constrain Wi-Fi recovery to the actual failure

**Evidence:** `bin/lidwise:574`, `:672`, `:750`, `:810`, `:823`.

The service-layer DHCP recovery unconditionally writes a temporary client ID and then clears it. It does not read the existing IPv4 method or client ID. A manually configured service with a missing route can therefore be converted to DHCP; an existing DHCP client ID is lost. The isolated probe confirmed two `-setdhcp` writes with no read of the service's previous configuration.

The classifier recognizes a non-Wi-Fi default route, but the recovery loop still escalates `portal` and `deadlink` by bouncing Wi-Fi. An Ethernet/VPN/upstream problem or an unavailable Apple probe can therefore trigger changes to the wrong interface. Captive portals are bounced after five minutes, despite the README saying they are left alone. Manually turning Wi-Fi off is also undone automatically.

**Fix:** preserve network configuration; never change a static service to DHCP. Preserve the client ID or use a renewal method that does not rewrite it. Couple diagnosis and recovery to the same interface. Keep captive portals and upstream/non-Wi-Fi failures passive. Offer visible recovery Off/On controls and a cooldown for intentional radio-off. Surface diagnosis before offering a manual reset.

**Acceptance:** static IPv4, custom DHCP ID, Ethernet default route, VPN, unavailable probe, captive portal, intentional Wi-Fi off, and interruption between writes preserve configuration and avoid unrelated radio changes. Test the full recovery loop, not just its classifier.

### 5. P1 — Treat packaging, install, upgrade, and removal as tested product paths

**Evidence:** `scripts/build.sh:49`, `:90`; `scripts/install.sh:40`, `:47`, `:57`; `scripts/uninstall.sh:12`; `src/Lidwise.swift:1019`.

The build signs only the outer app. The thermal helper is an embedded Mach-O in `Contents/Resources`, a nonstandard location for compiled code, and remains linker/ad hoc signed without hardened runtime. A successful local `codesign --verify --deep --strict` does not establish that all executable code meets notarization requirements. Move that executable to `Contents/Helpers` or another supported code directory and update its lookup path. Sign it with the same Developer ID, hardened runtime, and timestamp before signing the app, then notarize and assess the final extracted artifact. Reject any remaining ad hoc executable in a distribution candidate. See [Apple's signing guidance](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/), [code placement guidance](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html), and [notarization failure guidance](https://developer.apple.com/documentation/security/resolving-common-notarization-issues).

The installer deletes the previous app before the new install, privilege setup, and guardian bootstrap have all succeeded. Unknown power state does not block upgrade. It can leave an incomplete installation on failure, or leave a manually launched old app process running. The uninstaller relies on the wrapper to restore sleep; a missing wrapper skips that step. Both scripts need fresh-install, upgrade, rollback, and incomplete-install tests.

Disabling “Show in menu bar at login” calls `launchctl bootout` before removing the plist. If this app is running as that job, bootout can terminate the app before deletion. “Enable awake mode at login” can also be selected while login launch is off. Treat these as one coherent startup configuration and test the launchd-managed case.

**Acceptance:** extracted signed package installs cleanly without developer tools; canceled privilege setup and copy/bootstrap failures restore the prior app, wrapper, plists, and loaded jobs; upgrade refuses unknown/active state and exits every prior app instance before starting at most one replacement when appropriate; login settings apply without self-termination; removal restores sleep even after partial file loss. Test fresh install, launchd-managed upgrade, and manually launched upgrade separately. Logout/login and reboot require real-device checks.

### 6. P1 — Reconcile the published version with the tested version

The public [latest release](https://github.com/proofofreach/Lidwise/releases/latest) resolves to **v1.0.0**, published August 14. Local `VERSION` says **1.2.0**, whose changelog is still “unreleased.” Public `main` was `3cbc2b6`; the reviewed local `HEAD` was `acd5cdc`. The local 1.0 ZIP has neither the crash guardian nor the agent scanner. The stored local 1.2 ZIP includes both, but neither helper matches current source.

Checksums for all three existing ZIPs pass. That proves archive integrity, not freshness or current behavior. Do not send new users to an old package while describing newer safeguards.

**Fix:** freeze an exact source revision, preserve/review the pending scanner fix, rebuild and validate a single candidate, generate checksums from it, and align version, changelog, documentation, tag, and release asset. Make the final gate inspect the extracted archive. Publish only after the safety and hardware gates pass.

## Accuracy and usability improvements

### Agent status needs more honest semantics

`bin/lidwise-agent-scan:51` and `:59` treat a quiet session as completed after ten minutes. Claude completion is never parsed; Codex completion uses exact text matching rather than JSON structure. Nested `.jsonl` files, including subagents, count as independent sessions.

Isolated examples: a Claude log quiet for 601 seconds becomes `completed`; a nested subagent becomes another active session; valid JSON with spaces around `"type": "task_complete"` becomes active. The first is the important product error: silence is not successful completion. The whitespace example demonstrates parser brittleness, not a claim about the current vendor's serialization format.

Use `Working`, `Quiet`, `Finished` only when evidenced, and `Unknown`/`Disconnected` where appropriate. Prefer opt-in lifecycle hooks and a generic local activity protocol later. Until then, label results estimated, group child sessions, and avoid “completed” notifications inferred from age. Keep this observation completely separate from awake ownership.

### Streamline the main panel

Preserve the existing dark panel and one-click control. The rendered panel has a clear status header, useful countdown, and sensible Settings disclosure. It does not need a visual redesign.

The fault render exposes a specific layout issue: the battery floor and captive-portal instruction both truncate in the safety rail (`src/Lidwise.swift:412`, `:512`). Let fault messages wrap or expand into a separate actionable row. Critical recovery instructions must remain readable. Preview evidence: [normal](review-assets/menu-collapsed.png), [settings](review-assets/menu-expanded.png), [fault state](review-assets/menu-fault.png).

Recommended default content:

1. **Keep Mac awake** — one toggle, actual state, and “Until 4:30 PM · 2h left.”
2. **Duration** — 30m / 1h / 2h / 6h; all remain within the existing safety ceiling. An explicit extension must not silently defeat that ceiling.
3. **Safety** — battery floor, thermal availability, and recovery readiness; faults expand with a concrete repair action.
4. **Activity** — collapsed summary when present; expand to see provider/session details and any registered goals.
5. **Settings** — startup, recovery, notifications, shortcut, diagnostics, About/version, and update check.

Remove the duplicate toggle row once the primary toggle has verified keyboard access; retain the global shortcut. Hide an empty Goals row and undetected providers. Move “Observed only — agents never control sleep” into the Activity explanation. The current label “Work window” requires learning a term for a basic power control.

Put “Recovery off / on” in settings rather than requiring an environment variable. Add a read-only “Check setup” action with copyable diagnostics. Keep normal operation quiet; agent transition notifications are already opt-in in code.

Define Quit explicitly. Currently quitting the UI does not end the shell-owned awake session. Preserve that separation where intentional, but label it “Quit menu bar app” with the remaining duration, and expose “Turn off and quit.” Do not silently change your daily-use behavior.

### Reduce internal complexity where it changes outcomes

- Split the 1,263-line shell file by responsibility: session ownership/recovery, network observation/recovery, and job/agent observation. Keep safety independent of optional observation work.
- Replace parsing human-readable CLI output with a versioned `status --json` contract. Emit human text separately. Persist the actual session policy so another shell or UI does not display its own default floor/deadline.
- Use one coordinator for refresh and command execution. Give subprocesses timeouts and consume both output streams. Keep expensive log scanning out of safety heartbeats.
- Avoid rebuilding the whole SwiftUI card on each state application; update one observable state. This is lower priority than command correctness.
- On a later architecture pass, compare a small authenticated `SMAppService`/XPC helper with the shell + sudoers design. It offers a clearer lifecycle and trust boundary but adds installation, signing, migration, and security work. It is not a prerequisite for proving the bounded shell fixes.
- Prefer event notifications for power/thermal changes over spawning readers repeatedly when the architecture is ready. One local scanner run measured approximately 0.21 seconds; this is not a battery benchmark and does not justify an urgent performance rewrite.
- Prune old observed-session records and bound logs. The scanner recursively rewrites local records and applies permissions to the whole observed-agent tree; growth should not slow a safety check.

## Current competitors

Checked September 15, 2026. These are primary-source feature comparisons, not an independent safety certification. Release activity is context, not proof of reliability.

| Project | Already in README? | Documented capabilities relevant here | What to learn |
|---|---|---|---|
| [Keepresso](https://github.com/gyorgysh/keepresso) | No | Broad agent hooks, per-session activity, manual/timed sessions, end warnings, scheduled AI wake, setup flow, diagnostics, Shortcuts, and updates. Latest release v1.25.0 was September 14. | My assessment: closest feature competitor. Adopt reliable status and simple duration controls; avoid matching its entire toolkit. |
| [Lidless](https://github.com/nghialuong/Lidless) | Yes | Authenticated helper architecture, adjustable time/battery/charging policies, notarized DMG, Sparkle updates, shared tested policy logic. | Useful benchmark for installation and lifecycle. Its current README does not document agent mode; do not present the old UI observation as a newly verified fact. |
| [Hold My Lid](https://holdmylid.app/) | No | Agent hooks, broader provider support, quick pause, configurable battery/AC behavior, Homebrew install. | Explicit signals beat inference. Its closed-lid claims and bag-use marketing were not validated here; do not copy those claims. |
| [goguma](https://github.com/junnam586/goguma) | No | Scheduled wake, job history, command-scoped holds, agent integrations, CLI plus service-backed viewer. | Stronger for “wake for a future job.” That is a separate product expansion, not a launch requirement. |
| [LidAwake by NeoSpecies](https://github.com/NeoSpecies/LidAwake/blob/main/README.en.md) | No | Published lid-close measurement method, reproducible probe, JSON status, diagnostics, event-driven architecture and idle-exit claim. | Copy the evidence standard. Distribution docs disclose unsigned/unnotarized packaging; latest release metadata had no attached assets, so it is an engineering benchmark rather than proven distribution polish. |
| [Lid Awake by thuongtin](https://github.com/thuongtin/lid-awake) | No | Signed/notarized releases, signed update feed, explicit helper trust boundary, setup/security documentation. | Clear capability reporting. Current public builds are Apple Silicon only. |
| [StayUp](https://github.com/NongKnot/StayUp) | No | Opt-in activity receipts, onboarding, helper coverage indicators, update controls, remote GUI support. | Say when closed-lid coverage is unavailable. Its broader toolkit is not necessary here. |
| [Amphetamine](https://apps.apple.com/us/app/amphetamine/id937984704) | Yes | Mature trigger system, broad session controls, familiar App Store distribution. | Keep comparisons precise: its closed-display mode exists and documents power-transition caveats and an optional script/authentication path. |
| [Lungo](https://sindresorhus.com/lungo) | Yes | Focused interaction, durations and automation through URL schemes/Shortcuts. | Simplicity benchmark. Its own FAQ excludes standalone closed-lid use without charger and external display. |
| [KeepingYouAwake](https://github.com/newmarcel/KeepingYouAwake) | Yes | Small open-source utility, simple timed sessions and established distribution. | Scope discipline. Its own FAQ explicitly excludes closed-lid operation. |
| [Tamp](https://github.com/vyskoczilova/tamp) | No | Shows external sleep assertions alongside its own sessions; CLI. | Explain who is keeping the Mac awake. Adjacent tool, not established standalone clamshell support. |
| [macowl](https://github.com/rgcsekaraa/macowl) | No | Focused menu utility and explicit recovery prompt for a machine left awake. | Transparent restart/recovery experience. |

Additional direct alternatives found: [LidAwake by TurboKach](https://github.com/TurboKach/LidAwake), [LidAwake-Mac by deezeddd](https://github.com/deezeddd/LidAwake-Mac), [Insomniac by Vatsal057](https://github.com/Vatsal057/Insomniac), and [vigil](https://github.com/dbuskariol/vigil). These confirm that lid-close toggling itself is crowded. This is a bounded search, not a claim that no further projects exist.

**Positioning:** “Keep this Mac awake for a bounded session you control, with visible recovery.” Your combination of manual authority, CLI access, and optional monitoring suits interrupted and multi-job work. Free/open source, agent support, and Wi-Fi features are each available elsewhere; none alone establishes an advantage. Keepresso now includes network diagnostics and user-invoked recovery, so do not imply that all competing apps lack networking tools.

## Required documentation corrections

- Correct README and SECURITY networking claims: current code does not ping the gateway and does eventually bounce portals/upstream failures.
- Document agent notifications as opt-in and make “completed” semantics truthful.
- Remove the obsolete statement that Intel testing is needed “before version 1.0 is published.” Declare exactly which hardware and OS combinations have been tested.
- Keep the ventilation warning. Do not guarantee heat safety or that the app keeps an individual process/network job alive.
- Explain logout, reboot, Quit, external sleep blockers, and system-wide ownership. The existing user's LaunchAgent is not a machine-wide guardian across logout.
- Update release checklist owner/contact placeholders using verified repository settings, and verify private vulnerability reporting is enabled. MIT contributor attribution is present; no license-content defect was identified.
- Provide a clear manual route to the verified signed release. Automatic updates can follow.

Optional documentation/UI polish for Release 2: shorten the 544-line README; move detailed CLI, network, troubleshooting, and comparison material to dedicated guides; add About/version, support/report-bug, and update-check UI. These improve usability but do not gate the safety fixes.

## Implementation sequence and exit criteria

### Release 1: trustworthy existing behavior

1. Fix state/result reporting and serialize UI commands.
2. Fix transactional session ownership, process identity, runtime files, and recovery retirement.
3. Make network recovery preserve configuration and act only on appropriate Wi-Fi failures.
4. Correct agent completion labels and documentation, preserving observation-only behavior.
5. Test installer rollback, partial uninstall, login controls, and final nested signing.
6. Test every advertised CPU, OS, lid, power, login, and logout path, or narrow support claims to the configurations actually tested. Freeze and package one verified candidate; align public materials and release artifacts.

**Exit:** every blocker above passes its acceptance checks. A clean extracted download passes Gatekeeper; power restoration is observed on failure; documented hardware support matches evidence. Passing today's tests alone is insufficient.

Required real-device matrix, still unverified in this audit:

| Scenario | Required observation |
|---|---|
| Lid close on AC and battery, without external display | Work continues during an authorized session; sleep resumes after it ends. |
| Unplug/replug and battery floor | Correct policy and restoration across power changes. |
| Timer expiry and interrupted activation | Deadline is honored and incomplete activation restores normal sleep. |
| Kill/freeze the app and guard separately | Recovery occurs within the documented bound; unrelated work is untouched. |
| Logout/login and reboot | No unmanaged persistent sleep block; startup choices match actual behavior. |
| Missing permission or thermal helper | Activation is refused or clearly unavailable; UI never claims full protection. |
| Static/DHCP Wi-Fi, captive portal, VPN, Ethernet, intentional radio-off | Original settings preserved; recovery targets only a recoverable Wi-Fi failure. |
| Clean install, failed upgrade, incomplete uninstall | Gatekeeper accepts the candidate and lifecycle failures preserve recoverability. |
| Intel and Apple Silicon; minimum supported and current macOS | Publish only support claims backed by these observations. |

### Release 2: easier daily use

Add duration presets, a visible network-recovery setting, coherent startup options, diagnostics, and quieter optional Activity disclosure. Preserve the dark panel, hotkey, defaults, and user's manual control. Use a focused UI verification pass for keyboard, VoiceOver, narrow/truncated text, fault states, and current macOS appearance/accessibility settings.

### Later, only if users need it

Authenticated helper migration, signed automatic updates, lifecycle-hook adapters, and event-driven monitoring. Defer scheduled wake, agent-owned sleep, fan control, remote displays, extensive trigger engines, and a rebrand. They expand the product and its failure surface.

## File coverage

| Files | Review result |
|---|---|
| `.gitignore`, `VERSION` | Generated outputs are ignored; version needs release reconciliation. |
| `README.md`, `SECURITY.md`, `RELEASE_CHECKLIST.md`, `CHANGELOG.md`, `LICENSE` | Read in full; documentation drift and release gates listed above; MIT license present. |
| `assets/app-icon.png` | Visually inspected; no launch-blocking asset issue. |
| `src/Lidwise.swift` | State/command, startup, custom menu, placement, accessibility, and preview paths reviewed. |
| `src/ThermalState.swift` | Simple pressure-state reader; builds for both architectures; report missing/unknown sensor capability in UI. |
| `src/makeicon.swift` | Read generator and inspected image; no launch blocker. |
| `bin/lidwise`, `bin/lidwise-agent-scan` | Read in full; isolated failure probes and existing tests run; findings above. |
| `scripts/build.sh`, `scripts/check.sh`, `scripts/package.sh`, `scripts/notarize.sh` | Build/check run; packaging and notarization paths reviewed; existing ZIPs inspected; no Apple submission performed. |
| `scripts/install.sh`, `scripts/uninstall.sh`, `scripts/write-guardian-plist.sh` | Read in full; plist test passed; real install/uninstall not run on the daily-use machine. |
| `tests/test-guardian-plist.sh`, `tests/test-lidwise-agent-discovery.sh` | Passed; scanner whitespace/quiet/child-session and command ownership boundaries remain uncovered. |
| `tests/test-lidwise-goal-monitoring.sh`, `tests/test-lidwise-goals.sh` | Passed; tests establish observation does not own awake state. |
| `tests/test-lidwise-link-state.sh`, `tests/test-lidwise-network-notifications.sh` | Passed; current tests pin the DHCP writes without testing preservation or the complete recovery loop. |
| `tests/test-lidwise-safety.sh` | Passed; mocked guard/guardian checks cover valuable cases but not real logout, process death, concurrent commands, or hardware behavior. |

## Review audit trail

An independent fresh-context review used `gpt-5.6-sol` at `xhigh`, following the adversarial-plan-review skill. Initial verdict: **ship the plan with changes; current app is not ready for unattended public use**.

| Reviewer amendment | Disposition | Verification and change |
|---|---|---|
| Add external ownership to blocker 2 | accepted-verified | `status` and `toggle` use the global flag; `off` clears it without checking ownership. Added explicit external state and override acceptance. |
| Correct thermal executable signing/placement | accepted-verified | Build places it in Resources and signs only the app; direct inspection found linker/ad hoc signing. Added relocation, lookup update, inside-out signing, and extracted-executable checks. |
| Test running app instances and full upgrade rollback | accepted-verified | Installer stops only a known launchd login job. Added separate manual/managed upgrade cases and restoration of app, wrapper, plists, and loaded jobs. |
| Separate cosmetic work from release gates | accepted-verified | README length and About UI do not affect recovery. Moved them to Release 2; made tested hardware claims explicit. |
| Tighten positioning and evidence language | accepted-verified | Mandatory timeout contradicts “until you choose”; feature documentation does not certify superiority. Revised the tagline and table heading; marked the closest-competitor assessment as editorial. |

The reviewer challenged manual authority because explicit agent hooks could save battery and competing apps already offer manual sessions. The current age-based observer is not reliable enough to own sleep. The conservative default survives; exclusivity does not. No value decision already made by the user was reopened.

All initial amendments are incorporated. The reviewer reread the revised plan and returned **ENDORSED**. This endorses the audit and implementation sequence, not the current unfixed app.
