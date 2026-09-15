# Network diagnosis

Network monitoring is optional and read-only. It distinguishes online, captive
portal, no IP address, unassociated Wi-Fi, radio off, unreachable upstream, and
unknown states. A default route through Ethernet or a VPN is not treated as a
Wi-Fi failure.

```bash
vibecaf netdiag
vibecaf netlog
vibecaf config set recovery off
vibecaf config set recovery on
```

`recovery` is the compatibility name of the stored monitoring setting. This
candidate reports `network_recovery_available: false`: automatic DHCP and radio
changes are disabled. Current macOS has no documented `networksetup -renewdhcp`
command. Rewriting `-setdhcp` can erase a custom client ID or convert a static
service, and radio resets can interrupt unrelated traffic. The app does neither.

If DHCP has failed, inspect the active network service in System Settings →
Network → Details → TCP/IP. Renew its DHCP lease there when appropriate. For a
portal, open a browser and sign in. If Wi-Fi is off intentionally, leave it off.
For Ethernet, VPN, or upstream failures, inspect that connection first.

The connectivity probe requests Apple's captive-portal endpoint over HTTP.
That endpoint can be blocked or redirected. A failed probe alone does not prove
that the Internet is unavailable. Cached results expire and unknown remains unknown.
No Wi-Fi credentials are read or stored. See [Security](../SECURITY.md).

## Background monitoring

An awake session uses one optional worker for network, agent and goal checks.
Network checks normally wait 20 seconds between probes; agent/goal scans run
about once a minute and have a 10-second execution limit. A shared scan can delay
the next network probe by up to that limit, plus process termination overhead.
Network probes have a six-second HTTP timeout. These checks never delay the
independent safety guard or crash guardian.

Turning network monitoring off leaves agent observation running and hides cached
network results. With awake mode off, the menu app refreshes activity on demand
and on its timer; no persistent optional worker is needed.

With the menu open as an app, expected persistent processes are:

| State | Processes |
|---|---|
| Awake mode off | Menu app, launchd recovery guardian |
| Awake session | Menu app, recovery guardian, safety guard, `caffeinate`, shared observer |

Short-lived status commands, probes, scans and shell sleep children also appear
in process listings. The guard, guardian and `caffeinate` remain separate because
they provide policy checks, independent recovery and macOS sleep assertions.
