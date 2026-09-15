# Security model

Closed-Lid Awake changes a system-wide power setting. It cannot guarantee that a
job will continue, that hardware will stay cool, or that two competing power
utilities will cooperate. Keep the Mac ventilated and out of enclosed bags.

## Privilege boundary

The installer uses administrator authorization to install a launchd job and a
per-account sudoers rule. That rule permits exactly:

```text
/usr/bin/pmset -a disablesleep 0
/usr/bin/pmset -a disablesleep 1
```

The app, shell helper, and guardian run as the signed-in account, never as root.
The system LaunchDaemon includes `UserName` explicitly; placing a user-writable
helper in the system launchd domain does not grant it root execution. Only the
fixed `pmset` calls cross the privilege boundary. Any process already running as
that account can use this narrow grant. It is not restricted to the app's signature.

Activation verifies noninteractive restoration while ignoring cached sudo
credentials. A temporary password cache is not durable recovery authorization.
The independent guardian uses the app's durable session record to restore sleep
when the primary guard fails. The system job is intended to survive logout and
restart at boot. Actual logout and reboot behavior remains a release test gate.

## Ownership and local files

Session mutations are serialized. The helper records a session ID and policy,
and checks recorded process identity before signaling its own children. An existing
external hold is not adopted. Sleep readback must succeed before recovery is retired.
The OS flag has no owner field: another tool changing it during an owned session
cannot always be distinguished. Avoid simultaneous sleep-control tools.

Private runtime data lives in a per-user directory under the temporary directory.
Durable state lives under `~/Library/Application Support/Closed-Lid Awake/`.
Runtime and state directories are validated for ownership, permissions and symlinks.
These controls prevent cross-user interference; they do not defend against arbitrary
malicious code already running as the same user.

The guardian is installed at
`/Library/LaunchDaemons/app.closedlidawake.guardian.<uid>.plist` and runs as that user.
Installation migrates the old user LaunchAgent. The guardian's launchd stdout and
stderr go to `/dev/null`; the helper maintains bounded diagnostic logs.

## Network behavior

Monitoring requests `http://captive.apple.com/hotspot-detect.html`. This exposes the
usual connection metadata to the endpoint and local network. It sends no agent
content. A blocked or redirected probe is not conclusive proof of lost connectivity.

This candidate does not write DHCP settings, alter client IDs, change static IPv4,
or toggle Wi-Fi. It preserves intentional radio-off and treats Ethernet/VPN routing
separately. Diagnostics contain no Wi-Fi passwords.

## Agent observation and notifications

Optional local observation reads process information and recent session-log records
for Claude Code and Codex. It derives activity and explicit completion events locally;
quiet activity is not completion. Observation does not own the sleep session.
The app does not intentionally persist or transmit transcript prompts, responses,
or tool arguments. Cached summary records contain status metadata.

Agent notifications are opt-in. A user-configured `VIBECAF_NTFY_URL` sends notification
text to that endpoint. Goal names and messages can contain information you supplied;
review them before enabling remote notifications. Public ntfy topics are not private.
No analytics service or automatic project telemetry is included.

## Reporting a vulnerability

Use [GitHub private vulnerability reporting](https://github.com/proofofreach/ClosedLidAwake/security/advisories/new).
The repository setting was verified enabled on September 15, 2026. Do not publish
exploit details in a public issue. The repository is maintained at
[proofofreach/ClosedLidAwake](https://github.com/proofofreach/ClosedLidAwake).
