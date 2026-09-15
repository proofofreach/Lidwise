# Closed-Lid Awake

Keep your Mac awake for a bounded session you control.

A native menu-bar app and CLI for manual closed-lid work, with a battery floor,
thermal checks, a deadline, and independent sleep restoration. Optional local
activity monitoring shows Claude Code, Codex, and registered jobs. Activity does
not decide when your Mac sleeps.

**1.2 is an unreleased community candidate.** The launch review found safety and installer
issues in earlier code. Implementation and local tests are in progress. Do not
assume an older download contains the candidate safeguards. See the
[release gates](RELEASE_CHECKLIST.md) and [implementation evidence](docs/IMPLEMENTATION_STATUS.md).

> Keep the Mac on a hard, ventilated surface. Never run it awake in a closed bag.
> Software checks do not guarantee thermal safety or keep a particular job alive.

## Daily use

1. Open **Closed-Lid Awake** and use **Check setup**.
2. Choose a duration and turn awake mode on. Wait for verified status.
3. Close the lid only when the app reports an owned session with recovery ready.
4. Turn it off when finished. The deadline, battery floor, or thermal policy can
   end the session earlier.

The primary control and global shortcut operate the same session. Repeated
`on` calls do not extend its deadline. An external sleep hold is shown separately
and remains under the other tool's control.

**Quit menu bar app** leaves the session and recovery running. **Turn off and
quit** first verifies sleep restoration. A per-user system launchd job is intended
to recover sessions across logout and reboot; those paths still require real-device
validation before this candidate is released.

## Install

The community release is free, ad hoc signed, and not notarized by Apple. No Apple
Developer membership or App Store account is needed to use or publish it.
Use the version whose notes identify its verification and hardware status:
[releases](https://github.com/proofofreach/ClosedLidAwake/releases).
The public latest release may precede this candidate.

Extract the archive, open Terminal in its folder, then run:

```bash
./install.sh
```

The installer places the app in `~/Applications`, a `vibecaf` wrapper in
`~/.local/bin`, and an unprivileged recovery job in `/Library/LaunchDaemons`.
Administrator authorization installs that job and a narrow sleep-control rule.
Because the community build has no verified Developer ID, macOS may block first
launch. Follow [Apple’s Open Anyway instructions](https://support.apple.com/en-us/102445)
in System Settings → Privacy & Security after reviewing the download source.
Managed Macs may prohibit this exception. Do not disable Gatekeeper globally.
An upgrade requires verified normal sleep and rolls back if staging or setup fails.
No Xcode tools are needed to install a built archive.

For local development, install Xcode Command Line Tools, then:

```bash
./scripts/check.sh
./scripts/build.sh
RELEASE_MODE=community ./scripts/package.sh
```

Local builds are ad hoc signed unless a Developer ID identity is supplied. Passing
local signature checks does not make them notarized. The build emits arm64 and
x86_64 binaries targeting macOS 13; compilation is not proof of hardware support.
The current development host is Apple Silicon with macOS 26.6.2. The candidate's
lid, power, logout, and reboot matrix remains pending.

## Command line

```bash
vibecaf on --for 3600
vibecaf status --json
vibecaf off
vibecaf doctor
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

Report ordinary bugs through [GitHub issues](https://github.com/proofofreach/ClosedLidAwake/issues).
Use [private vulnerability reporting](https://github.com/proofofreach/ClosedLidAwake/security/advisories/new)
for security issues. Licensed under [MIT](LICENSE).
