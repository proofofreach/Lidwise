# Closed-Lid Awake

<div align="center">

<img src="assets/app-icon.png" alt="Closed-Lid Awake icon" width="240">

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue.svg)](https://www.apple.com/macos/)
[![Universal](https://img.shields.io/badge/Mac-Apple%20Silicon%20%2B%20Intel-black.svg)](#requirements)
[![GitHub release](https://img.shields.io/github/v/release/ProofOfReach/ClosedLidAwake)](https://github.com/ProofOfReach/ClosedLidAwake/releases/latest)

## Close the lid. Keep the run alive.

**A safety-bounded macOS menu-bar utility for long AI jobs, builds, renders, transfers, and remote sessions.**

### Quick install

[Download the latest release](https://github.com/ProofOfReach/ClosedLidAwake/releases/latest) → Unzip → Run `./install.sh`

</div>

---

## TL;DR

**The problem:** `caffeinate` blocks idle sleep, but closing a MacBook lid uses
a separate clamshell-sleep path. Your overnight agent run can still vanish the
moment the lid closes.

**The solution:** Closed-Lid Awake pairs `pmset disablesleep` with
`caffeinate`, puts the controls in your menu bar, and restores normal sleep
automatically at 20% battery, after six hours, or under unsafe thermal pressure.
A launchd guardian restores sleep if the main guard crashes.

Turn it on. Close the lid. Check the result from another device.

> [!CAUTION]
> Closed-Lid Awake prevents normal sleep. **Never put an awake Mac in a bag,
> sleeve, drawer, or other enclosed space.** Keep it on a hard, ventilated
> surface with clear airflow.

## Why use this?

| Feature | What it does for you |
|---|---|
| **Closed-lid operation** | Keeps local work running after the lid closes |
| **20% battery floor** | Restores normal sleep before an unattended Mac runs flat |
| **Six-hour dead-man timer** | Stops a forgotten awake session automatically |
| **Thermal guard** | Stops immediately at critical pressure or after sustained serious pressure |
| **Crash recovery** | A separate launchd guardian restores sleep if the session guard disappears |
| **Wi-Fi recovery** | Gives macOS bounded, backoff-aware chances to rejoin known networks |
| **Multi-goal monitoring** | Watches several jobs without making any job own the awake window |
| **Actionable alerts** | Reports battery, thermal, network, stalled, failed, and completed events |
| **One-click menu control** | Shows power, network, guard, and auto-off state at a glance |
| **Global hotkey** | Toggles awake mode with `⌃⌥A`, even if the icon is hidden |
| **Notch recovery** | Detects a menu-bar icon trapped behind a MacBook notch and tries safer positions |
| **No telemetry** | Sends no analytics, accounts, or usage data to the project |

## Why not just use `caffeinate`?

`caffeinate` solves idle sleep. It does **not** reliably solve lid-close sleep.
Closed-Lid Awake coordinates both macOS mechanisms and adds the controls needed
for unattended use.

| Capability | Normal macOS | `caffeinate` | Closed-Lid Awake |
|---|:---:|:---:|:---:|
| Allows normal idle sleep | Yes | No | No |
| Keeps running with lid closed | No | No | **Yes** |
| Restores normal sleep on command | — | Yes | **Yes** |
| Battery floor | No | No | **20%** |
| Hard session limit | No | Optional timer only | **Six hours** |
| Wi-Fi recovery | No | No | **Bounded watchdog** |
| Menu-bar status and hotkey | No | No | **Yes** |

### Compared with Amphetamine, KeepingYouAwake, and Lungo

Closed-Lid Awake is not a universal replacement for the established apps. It
is built for a narrower case: unattended work that must continue with the lid
closed and no external display attached.

| App | Lid closed without external display | Sessions and automation | Automatic safety | Wi-Fi recovery | Distribution |
|---|---|---|---|---|---|
| **Closed-Lid Awake** | **Yes** | Global work window, optional multi-goal telemetry, menu, hotkey, and CLI | **Battery, time, thermal, and crash recovery guards** | **Bounded reconnect watchdog** | GitHub; MIT source |
| **[Amphetamine](https://apps.apple.com/us/app/amphetamine/id937984704)** | **Yes** | Timed sessions, app/file/device/network/power triggers, hotkeys, and AppleScript | Optional low-battery auto-end | Not advertised | Mac App Store |
| **[KeepingYouAwake](https://github.com/newmarcel/KeepingYouAwake)** | No | Simple menu-bar sessions for a chosen duration | Avoids closed-lid operation by design | Not advertised | GitHub and Homebrew; MIT source |
| **[Lungo](https://sindresorhus.com/lungo)** | No, except Apple's charger + external-display clamshell mode | Preset durations, Shortcuts, URL scheme, and third-party CLI | Can deactivate on battery switch or screen lock | Not advertised | Mac App Store and Setapp |

“Not advertised” means the feature is absent from the product's official
feature documentation; it does not claim that no extension or workaround
exists. Comparison checked on August 14, 2026.

**Choose Amphetamine** if you want the broadest set of automatic triggers and
a conventional App Store install. **Choose Lungo** if you want a focused,
simple App Store utility. **Choose KeepingYouAwake** if you want a small
open-source wrapper around Apple's `caffeinate` command and can leave the lid
open.

**Choose Closed-Lid Awake** when closing the lid without an external display is
the requirement—not an edge case—and you want a fixed safety ceiling, Wi-Fi
recovery, CLI control, and auditable source. The tradeoff is a privileged
`pmset` rule and, for the current community build, a manual Gatekeeper approval.

## Quick start

```text
1. Install Closed-Lid Awake
2. Open it from ~/Applications
3. Click the moon icon and choose “Turn On”
4. Confirm that the menu reports “Awake mode: ON”
5. Leave the Mac on a hard, ventilated surface
6. Close the lid
```

The cup icon means awake mode is active. The app reports the current power
source, network state, guard state, and remaining time.

You can also press `⌃⌥A` anywhere or run:

```bash
vibecaf toggle
```

## Requirements

- macOS 13 or later.
- An Apple Silicon or Intel Mac.
- An administrator account for the recommended safety-guard permission.
- A hard, uncovered surface with clear airflow during closed-lid use.
- Xcode Command Line Tools only when building from source.

## Installation

### From a release

No Xcode or developer tools required.

> [!IMPORTANT]
> The current community build is ad hoc signed, not Apple-notarized. macOS can
> block its first launch. If that happens, open **System Settings → Privacy &
> Security**, find the blocked-app notice, and choose **Open Anyway**. Review
> the source and [security model](SECURITY.md) before granting access.

1. Download the ZIP from
   [Releases](https://github.com/ProofOfReach/ClosedLidAwake/releases/latest).
2. Unzip it.
3. Open Terminal in the extracted directory.
4. Run:

```bash
./install.sh
```

The installer places:

```text
~/Applications/Closed-Lid Awake.app
~/.local/bin/vibecaf
~/Library/LaunchAgents/app.closedlidawake.guardian.plist
```

It also asks for administrator approval to install a narrow `sudoers` rule.
The rule allows only:

```text
/usr/bin/pmset -a disablesleep 0
/usr/bin/pmset -a disablesleep 1
```

That permission lets the battery, time, thermal, and crash guards restore
normal sleep while the lid is closed. It does not grant the app a shell or
unrestricted administrator access. Read the complete
[security model](SECURITY.md).

To install without the rule:

```bash
./install.sh --without-sudoers
```

> [!WARNING]
> Without the rule, unattended safety recovery cannot reliably restore sleep
> because nobody can answer an administrator prompt behind a closed lid.

### From source

Building requires the Xcode Command Line Tools.

```bash
git clone https://github.com/ProofOfReach/ClosedLidAwake.git
cd ClosedLidAwake
./scripts/check.sh
./scripts/package.sh
```

The build creates a universal Intel and Apple Silicon app in `dist/`.

## How it works

```text
┌──────────────────────────────────────────────────────────────┐
│                    Closed-Lid Awake.app                      │
│  menu bar · global hotkey · state · login item · notch fix  │
└──────────────────────────────┬───────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────┐
│                         vibecaf                              │
│         owns the global work window and cleanup              │
└────────┬──────────────┬──────────────┬──────────────┬─────────┘
         │              │              │              │
         ▼              ▼              ▼              ▼
     pmset +        safety guard   Wi-Fi watchdog   goal registry
    caffeinate      time · battery  bounded recovery observation only
                     · thermal
         ▲
         │ restores normal sleep if the guard disappears
   launchd crash guardian
```

The helper treats awake mode as one owned session:

1. `pmset disablesleep 1` blocks clamshell sleep.
2. `caffeinate -i -m -s` blocks idle system and disk sleep.
3. The guard watches battery, elapsed time, and macOS thermal pressure.
4. An independent launchd guardian restores sleep after a guard crash or stale
   session heartbeat.
5. The optional watchdog monitors connectivity without reading Wi-Fi passwords.
6. The optional goal registry observes jobs but never starts or stops the work
   window.
7. Turning off always attempts `pmset disablesleep 0`, even if another state
   check fails.

The helper tracks only processes it starts. It does not kill unrelated
`caffeinate` processes.

## Command line

The menu-bar app and CLI control the same state.

```bash
vibecaf on            # Start an awake session
vibecaf off           # Stop it and restore normal sleep
vibecaf toggle        # Switch state
vibecaf status        # Fast local status
vibecaf status --net  # Status with a live network probe
vibecaf netlog        # Show recent watchdog activity
```

### Monitor several jobs

Goal monitoring is optional telemetry. Awake mode remains under your control.
A completion, failure, stall, or stopped process never turns awake mode off.

```bash
vibecaf goal add "API migration" --pid 12345
vibecaf goal add "Docs agent" --activity-file /tmp/docs-progress --stale-after 600
vibecaf goals --refresh
vibecaf goal complete "API migration" "merged"
vibecaf goal fail "Docs agent" "lost connection"
```

If you restart a stopped job, attach the same goal to its replacement PID:

```bash
vibecaf goal restart "API migration" --pid 23456
```

Use `goal touch`, `goal remove`, or `goals --summary` to update and manage the
registry. None of these commands changes system sleep state.

Example status:

```text
AWAKE MODE: ON
Lid-close sleep blocked: yes
caffeinate pid: 12345
Wi-Fi watchdog pid: 12346
Guard pid: 12347
Crash guardian: running
Auto-off in: 5h 42m
Battery floor: 20%
Thermal: nominal
Goals: 4 active · 1 stalled · 2 completed · 0 failed
Network: online
Power: AC 100%
```

## Safety behavior

Closed-Lid Awake reduces risk; it cannot eliminate it.

| Guardrail | Default | Purpose |
|---|---:|---|
| Battery floor | 20% | Restores sleep before battery exhaustion |
| Dead-man timer | 6 hours | Ends forgotten sessions |
| Critical thermal pressure | Immediate | Restores sleep at the highest macOS thermal state |
| Serious thermal pressure | 3 checks | Avoids reacting to one brief spike |
| Guard heartbeat | 3 minutes | Recovers from a crashed or frozen session guard |
| Network recovery limit | 3 failed cycles | Stops Wi-Fi thrashing |
| Passive retry window | 15 minutes | Gives macOS time to recover on its own |
| Display assertion | Disabled | Allows the display and lock screen to behave normally |

For guard testing, you can override the defaults for one shell session:

```bash
VIBECAF_DEADMAN_SECONDS=20 VIBECAF_GUARD_EVERY=5 vibecaf on
sleep 40
vibecaf status
```

Do not use test overrides for real unattended work.

## Wi-Fi recovery

When enabled, the watchdog:

1. Checks Apple's captive-portal test page.
2. Checks the local gateway if the internet test fails.
3. Leaves Wi-Fi alone during captive-portal or upstream failures.
4. Power-cycles Wi-Fi only after repeated link failures.
5. Stops cycling after three failed attempts and enters passive mode.

It uses networks already known to macOS. It never reads or stores Wi-Fi
credentials. Disable the watchdog for one session with:

```bash
VIBECAF_NO_NETWATCH=1 vibecaf on
```

## Notifications

The app sends local notifications for safety shutdowns, network transitions,
and goal stalls, stops, failures, recoveries, and completions.

For alerts on another device, set an [ntfy](https://ntfy.sh/) topic URL before
starting awake mode:

```bash
VIBECAF_NTFY_URL="https://ntfy.sh/a-long-private-topic-name" vibecaf on
```

Anyone who knows a public ntfy topic can receive its messages. Use a long,
unguessable topic or a private self-hosted server. Goal names and messages are
sent to that URL when remote alerts are enabled.

## Settings

### Start at login

Open the menu and enable **Show in menu bar at login**.

To start awake mode immediately after login, also enable
**Enable awake mode at login**. Use that option carefully: a reboot does not
preserve `pmset disablesleep`, so the app must start a new session.

### Change the hotkey

The default is `⌃⌥A`. Configure another key through macOS defaults, then
restart the app:

```bash
defaults write app.closedlidawake.ClosedLidAwake HotkeyKeyCode -int 0
defaults write app.closedlidawake.ClosedLidAwake HotkeyModifiers -int 3
```

Modifier values are additive:

| Modifier | Value |
|---|---:|
| Command `⌘` | 1 |
| Shift `⇧` | 2 |
| Option `⌥` | 4 |
| Control `⌃` | 8 |

## Troubleshooting

### Awake mode is on, but the Mac still sleeps

Run:

```bash
vibecaf status
pmset -g | grep SleepDisabled
```

The output must show `Lid-close sleep blocked: yes` and `SleepDisabled 1`. If
not, turn the app off, reinstall the privilege rule, then turn it on again.

### The menu-bar icon disappeared

It may be behind the MacBook notch or hidden by another menu-bar manager.

- Press `⌃⌥A` to toggle awake mode.
- Quit or move a few menu-bar items.
- Reopen the app and choose **Move icon out of the notch**.
- Run `vibecaf status` if you need an authoritative state check.

### Wi-Fi keeps disconnecting

Inspect the watchdog log:

```bash
vibecaf netlog
```

If a VPN, captive portal, or unusual network conflicts with probing, disable
the watchdog for that session:

```bash
VIBECAF_NO_NETWATCH=1 vibecaf on
```

### Normal sleep did not return

Turn the app off again, then verify the system state:

```bash
vibecaf off
pmset -g | grep SleepDisabled
```

The value must be `0`. If it is still `1`, restore it directly:

```bash
sudo pmset -a disablesleep 0
```

## Limitations

- **macOS only.** The app depends on AppKit, `pmset`, and `caffeinate`.
- **No reboot persistence.** macOS clears `disablesleep` during a reboot.
- **No heat guarantee.** The guard reacts to macOS thermal-pressure states. It
  cannot measure enclosure airflow or make closed-bag use safe.
- **No network guarantee.** Wi-Fi, VPNs, captive portals, routers, and remote
  services can still fail.
- **No power-loss protection.** A drained battery, unplugged charger, kernel
  panic, or forced shutdown ends the job.
- **No App Store build.** The power-control model requires a narrowly scoped
  privilege rule.
- **Apple can change this.** `pmset disablesleep` is undocumented behavior.

## FAQ

### Is this the same as `caffeinate`?

No. `caffeinate` blocks idle sleep. Closed-Lid Awake also controls the
clamshell-sleep setting used when the lid closes.

### Is the administrator rule safe?

It is deliberately narrow. Your account may run only the two fixed
`pmset disablesleep` commands without another password prompt. Review
[SECURITY.md](SECURITY.md) and the installer source before accepting it.

### Will it cook my Mac?

It can create unsafe conditions if you block airflow. The thermal guard reacts
to system pressure, but it cannot make an enclosed Mac safe. Keep the Mac
uncovered on a hard surface. Never run it inside a bag.

### Does it work on Intel Macs?

The release is a universal `arm64` and `x86_64` build. Intel hardware still
needs release testing before version 1.0 is published.

### Does it collect data?

No telemetry or analytics. The optional network watchdog contacts Apple's
captive-portal test page and your local gateway. See [SECURITY.md](SECURITY.md).

### Can it keep Claude, Codex, a build, or a transfer running?

It keeps macOS awake. It cannot prevent the individual process, terminal,
network, remote service, or power source from failing.

## Uninstall

From an extracted release:

```bash
./uninstall.sh
```

From a source checkout:

```bash
./scripts/uninstall.sh
```

The uninstaller restores normal sleep before it removes the app, command-line
wrapper, login item, and privilege rule.

## Contributing

Bug reports and pull requests are welcome. Useful contributions include:

- Testing across Intel and Apple Silicon Macs.
- Testing on different macOS releases.
- Hardening power-state cleanup.
- Improving network recovery without aggressive radio cycling.
- Making privilege boundaries easier to audit.

Before opening a pull request, run:

```bash
./scripts/check.sh
```

## License

MIT. Free to use, inspect, modify, and distribute.

See [LICENSE](LICENSE).
