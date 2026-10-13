# Security model

Lidwise changes system power behavior. Review this model before use.

## Administrator privilege

Only `pmset` needs privilege. The installer creates a per-account `sudoers`
file that permits exactly:

```text
/usr/bin/pmset -a disablesleep 0
/usr/bin/pmset -a disablesleep 1
```

The app and its shell helper remain unprivileged. The rule does not permit an
arbitrary shell, arbitrary `pmset` arguments, or execution as another user.

The rule is important to the safety guard. When nobody can answer an
authentication dialog, the guard needs a noninteractive way to restore normal
sleep at the battery floor or time limit.

## Process ownership

The helper records the PIDs of only the `caffeinate`, guard, and watchdog
processes that it starts. It does not terminate unrelated `caffeinate`
processes.

## Network behavior

The watchdog requests `http://captive.apple.com/hotspot-detect.html` to test
internet access. If that fails, it pings the local default gateway. After
repeated link failures, it can power-cycle Wi-Fi with `networksetup` so macOS
retries known networks. It does not read or store Wi-Fi credentials.

## Local files

Runtime PID and state files use `/tmp/lidwise-*.<uid>`. Logs are written to:

```text
~/Library/Logs/lidwise-net.log
~/Library/Logs/lidwise.log
```

No telemetry is collected.

## Reporting a vulnerability

Do not publish exploit details in a public issue. Use GitHub's
[private vulnerability report](https://github.com/ProofOfReach/Lidwise/security/advisories/new)
so the maintainers can investigate before disclosure.
