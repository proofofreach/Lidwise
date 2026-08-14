# Security model

Closed-Lid Awake changes system power behavior. Review this model before use.

## Administrator privilege

Only `pmset` needs privilege. The installer creates a per-account `sudoers`
file that permits exactly:

```text
/usr/bin/pmset -a disablesleep 0
/usr/bin/pmset -a disablesleep 1
```

The app and its shell helper remain unprivileged. The rule does not permit an
arbitrary shell, arbitrary `pmset` arguments, or execution as another user.

The rule is important to the safety guard and crash guardian. When nobody can
answer an authentication dialog, they need a noninteractive way to restore
normal sleep at the battery floor, time limit, thermal limit, or after a guard
failure.

## Process ownership

The helper records the PIDs of only the `caffeinate`, guard, and watchdog
processes that it starts. It does not terminate unrelated `caffeinate`
processes.

The launchd crash guardian acts only when the app's durable ownership record
exists. It does not clear `disablesleep` set by another tool when no ownership
record exists.

## Network behavior

The watchdog requests `http://captive.apple.com/hotspot-detect.html` to test
internet access. If that fails, it pings the local default gateway. After
repeated link failures, it can power-cycle Wi-Fi with `networksetup` so macOS
retries known networks. It does not read or store Wi-Fi credentials.

## Local files

Runtime PID and network-state files use `/tmp/vibecaf-*.<uid>`. Durable session
and goal records are stored under:

```text
~/Library/Application Support/Closed-Lid Awake/
```

The app installs an unprivileged crash-recovery LaunchAgent at:

```text
~/Library/LaunchAgents/app.closedlidawake.guardian.plist
```

Logs are written to:

```text
~/Library/Logs/vibecaf-net.log
~/Library/Logs/closedlidawake.log
~/Library/Logs/closedlidawake-guardian.log
```

No telemetry is collected. If `VIBECAF_NTFY_URL` is set, notification titles,
goal names, and messages are sent to that user-selected endpoint. Public ntfy
topics must be treated as shared secrets.

## Reporting a vulnerability

Do not publish exploit details in a public issue. Use GitHub's
[private vulnerability report](https://github.com/ProofOfReach/ClosedLidAwake/security/advisories/new)
so the maintainers can investigate before disclosure.
