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
