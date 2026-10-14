# Lidwise

![Lidwise — Close the lid. Keep going.](assets/lidwise-hero.png)

Keep your Mac awake for a timed session or Full On with no timer.

Previously named **Closed-Lid Awake**. Upgrading installs `Lidwise.app` and the
`lidwise` CLI, updates existing login paths, and retains an existing `vibecaf`
command as a compatibility alias. Settings, session storage, the bundle ID, and
recovery job identifiers keep their original names so upgrades preserve ownership
and recovery. Historical screenshots and hardware records describe earlier builds.

A native menu-bar app and CLI for manual closed-lid work, with a battery floor,
thermal checks, an optional deadline, and independent sleep restoration. Optional local
activity monitoring shows Claude Code, Codex, and registered jobs. Activity does
not decide when your Mac sleeps.

**1.2.0 is an unreleased community candidate.** Independent code review,
automated checks, and local installation have passed. Some
real-device and clean-download checks remain before public release. Older
downloads may not contain these safeguards. See the [release gates](RELEASE_CHECKLIST.md)
and [test evidence](docs/HARDWARE_VALIDATION.md).

The current source also adds expiry warnings, explicit session extension, saved
power limits, session history, agent attention signals, and a guided lid test.
Earlier installation and hardware results do not certify these additions.

> Keep the Mac on a hard, ventilated surface. Never run it awake in a closed bag.
> Software checks do not guarantee thermal safety or keep a particular job alive.

## Daily use

1. Open **Lidwise** and use **Check setup**.
2. Choose a duration or **Full On** (no timer), then turn awake mode on. Wait for verified status.
3. Close the lid only when the app reports an owned session with recovery ready.
4. Turn it off when finished. The deadline, battery floor, or thermal policy can
   end the session earlier.

The primary control and global shortcut operate the same session. Repeated
`on` calls do not extend its deadline. An external sleep hold is shown separately
and remains under the other tool's control.

**Full On** has no timer. It stays awake until you turn it off or a battery,
AC-only, thermal, or recovery cutoff ends the session. Choose it before starting
a session; changing the selector during a session affects the next session.
The CLI equivalent is `lidwise on --for 0`.

For timed sessions, the app warns in the final five minutes. **Add 30 minutes** extends an eligible
session within the six-hour total limit. Settings can save a battery floor and
an AC-only requirement for the next session. Session history explains why a
session stopped and whether normal sleep was verified. The guided lid test
measures one run without changing your power settings.

Network, agent, and job monitoring share one optional background worker during
awake sessions. Sleep protection and independent recovery remain separate.
Temperature status uses **Normal**, **Warm**, **High**, and **Critical**.
The battery floor applies even with a charger connected. At or below that floor,
Lidwise ends an active session and refuses a new one until the battery recovers.

**Quit menu bar app** leaves the session and recovery running. **Turn off and
quit** first verifies sleep restoration. A per-user system launchd job is intended
to recover sessions across logout and reboot; those paths still require real-device
validation before this candidate is released.

## Install

The community build is free, ad hoc signed, and not notarized by Apple. No Apple
Developer membership or App Store account is needed to use or publish it.
Use the version whose notes identify its verification and hardware status:
[releases](https://github.com/proofofreach/Lidwise/releases).
The published [v1.0.0 release](https://github.com/proofofreach/Lidwise/releases/tag/v1.0.0)
predates this candidate. To test 1.2.0 before publication, use the local development
steps below.

Download the ZIP and matching `.sha256` file. In their download folder, verify
the checksum (replace the filename for a different version):

```bash
shasum -a 256 -c Lidwise-1.2.0-macos-universal.zip.sha256
```

Continue only if the checksum reports `OK`. Extract the archive, open Terminal
in the extracted folder, then run:

```bash
./install.sh
```

The installer places the app in `~/Applications`, a `lidwise` wrapper in
`~/.local/bin`, and an unprivileged recovery job in `/Library/LaunchDaemons`.
Administrator authorization installs that job and a narrow sleep-control rule.
Terminal does not display password characters as you type. On Macs configured
to require authentication for every administrator command, several password
prompts are expected. A new prompt alone does not mean the previous password
failed. Wait for `Installed …/Lidwise.app` before opening the app.

Because the community build has no verified Developer ID, macOS may block first
launch. Follow [Apple’s Open Anyway instructions](https://support.apple.com/en-us/102445)
in System Settings → Privacy & Security after reviewing the download source.
Managed Macs may prohibit this exception. Do not disable Gatekeeper globally.
An upgrade requires verified normal sleep and rolls back if staging or setup fails.
No Xcode tools are needed to install a built archive.

For local development, install Xcode Command Line Tools, then:

```bash
./scripts/check.sh
RELEASE_MODE=community ./scripts/package.sh
```

The package command builds the app and verifies the extracted archive. The ZIP
and its checksum are written to `dist/`.

Local builds are ad hoc signed unless a Developer ID identity is supplied. Passing
local signature checks does not make them notarized. The build emits arm64 and
x86_64 binaries targeting macOS 13; compilation is not proof of hardware support.
Local testing on an Apple Silicon Mac with macOS 26.6.2 has covered AC and battery
lid-close operation, return to normal lid sleep, timer expiry, guard-crash
recovery, and the shared monitoring worker. Logout/reboot, remaining failure
cases, clean-download installation, and accessibility checks remain pending.
Intel and macOS 13 execution are unverified. The [hardware record](docs/HARDWARE_VALIDATION.md)
identifies tested builds and the limits of each observation.

## Command line

```bash
lidwise on --for 3600
lidwise extend --by 1800
lidwise status --json
lidwise off
lidwise history --json
lidwise doctor
```

Durations are limited to six hours. Network monitoring is read-only. Agent alerts
are opt-in, and a quiet transcript is not evidence that work completed.

## Guides

- [CLI and job monitoring](docs/CLI.md)
- [Network diagnosis](docs/NETWORK.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Alternatives and positioning](docs/COMPARISON.md)
- [Security and privacy](SECURITY.md)
- [Launch review](docs/LAUNCH_REVIEW.md)

## Remove

From the extracted release folder, run `./uninstall.sh`. From source, run
`./scripts/uninstall.sh`. Removal finds the app helper even if the CLI wrapper is
missing. If owned sleep restoration fails, it retains recovery files and permission.
An external sleep hold is preserved and reported.

Report ordinary bugs through [GitHub issues](https://github.com/proofofreach/Lidwise/issues).
Use [private vulnerability reporting](https://github.com/proofofreach/Lidwise/security/advisories/new)
for security issues. Licensed under [MIT](LICENSE).
