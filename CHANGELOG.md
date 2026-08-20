# Changelog

## 1.2.0 — unreleased

- Added automatic, local-only Claude Code and Codex session discovery.
- Added agent activity and restart notifications without giving agents control
  of the global work window.
- Rebuilt the menu around a compact work-window and session-fleet card.
- Restyled the whole menu as one dark panel: every action row now shares the
  card's palette, with icons, hover and keyboard highlight, check indicators,
  and shortcut glyphs; native key equivalents and accessibility are kept.
- Reorganised the menu around progressive disclosure: it opens to the card,
  the primary toggle, and Quit; startup options and tools live in an in-panel
  Settings drawer that expands in place and reopens collapsed. Check rows
  flip without closing the menu. If the icon is lost behind the notch, the
  menu opens with the drawer expanded and the fix highlighted.
- Agent discovery no longer counts MCP servers (`codex mcp-server`,
  `claude mcp serve`) or crash-reporter helpers as connected sessions, which
  produced a phantom "1 idle" Codex entry.
- Added `vibecaf agents` commands for per-session and aggregate status.
- Replaced the single radio-bounce network recovery with a state ladder:
  `link_state` classifies `radio_off | unassoc | noip | portal | deadlink |
  online` and each state gets its cheapest fix. A dead DHCP lease on a live
  association now recovers in ~9s instead of minutes.
- Renew DHCP at the service layer (`networksetup -setdhcp`), which needs no
  root. Retired the `ipconfig` sudoers grant: its interface-layer renew wedged
  the macOS Wi-Fi menu on "No Internet Connection" until reboot.
- Left captive portals to a human (grace period, never a radio bounce) and
  gave wedged-but-associated links a grace period before escalating.
- Added `vibecaf netdiag`, a read-only dry run of the recovery ladder, and an
  iPhone-hotspot indicator (by subnet — macOS redacts the SSID) to status and
  the menu bar.

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
