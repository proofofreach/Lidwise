# Changelog

## 1.2.0 — unreleased community candidate

- Enforce the battery floor on AC as well as battery power, including activation.
  A connected charger no longer bypasses low-battery protection.

- Renamed the app, CLI, source files, documentation, and release packages to Lidwise.
  Upgrade installation migrates the old app and login path with rollback support.
  Existing settings and recovery identifiers remain compatible.

- Add explicit bounded session extension and an advance expiry warning.
- Save next-session battery and charging-only policy; retain active session policy.
- Record a bounded local session history with reasons and restoration results.
- Add supported explicit agent attention/failure events and reversible adapter setup.
- Add guided read-only lid verification with a native measurement helper.
- Explain installation progress and the administrator authorization step.

- Consolidate network, agent and goal monitoring into one optional session worker;
  bound activity scans and preserve independent sleep recovery.
- Refresh agent activity while awake mode is off, without delaying power controls.
- Show plain temperature labels: Normal, Warm, High, and Critical.
- Recognize resumed Codex Desktop response-item activity so a previous completed
  turn does not leave an active task labeled finished.

- Add transactional session ownership, bounded duration settings, verified sleep
  restoration, private runtime state, and process identity checks.
- Distinguish unknown and externally controlled sleep state; preserve another
  tool's hold unless the user explicitly overrides it.
- Add versioned JSON status and read-only setup diagnostics.
- Improve the dark menu panel with verified command results, duration controls,
  optional Activity, coherent startup settings, and explicit quit choices.
- Observe Claude Code and Codex locally; quiet sessions no longer imply completion.
  Preserve exclusion of browser native-message hosts and MCP helper processes.
- Replace automatic DHCP and Wi-Fi mutations with read-only network diagnosis.
  Existing network configuration and intentional radio-off choices are preserved.
- Stage installations and roll back failures. Find the installed helper during
  removal even if its CLI wrapper is missing.
- Run the per-user recovery job in the system launchd domain, as the user, to
  support recovery across logout. Real-device lifecycle validation is pending.
- Move native helpers to Contents/Helpers, sign embedded code before the bundle,
  and verify the extracted archive against a source-input manifest.

The selected distribution route is a free GitHub community build, ad hoc signed
and not notarized. Apple Developer membership and App Store publication are optional.

This candidate is not yet certified for public unattended use. See RELEASE_CHECKLIST.md
and docs/IMPLEMENTATION_STATUS.md for outstanding evidence.

## 1.1.0 — 2026-08-14

- Added an independent launchd guardian for crash-safe sleep restoration.
- Added thermal-pressure shutdown at critical or sustained serious pressure.
- Added optional multi-goal monitoring that does not own the awake window.
- Added job restart support and stalled, stopped, failed, and completed alerts.
- Added local and optional ntfy alerts for safety and network transitions.
- Added thermal, guardian, and goal summaries to the menu and CLI status.

## 1.0.0 — 2026-08-14

- Added menu-bar and global-hotkey controls.
- Added closed-lid sleep prevention with automatic restoration.
- Added a 20% battery floor and six-hour dead-man timer.
- Added bounded Wi-Fi recovery and passive backoff.
- Added notch-aware menu-bar placement recovery.
- Added universal builds, installer, uninstaller, packaging, and notarization
  support.
