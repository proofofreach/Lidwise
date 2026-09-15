# Troubleshooting

## Setup or activation failed

Use **Check setup** or `lidwise doctor`. The app needs a working thermal helper,
a running guardian, and durable permission to restore sleep without an interactive
authentication dialog. A recently cached `sudo` password is not sufficient.
Reinstall from the verified release to repair setup after turning awake mode off.

Do not close the lid based on a requested toggle alone. Wait for verified status.
If status is unknown, keep the lid open until the cause is resolved.

## Sleep did not return

Run `lidwise status --json`. If the session is owned by this app, run `lidwise off`.
A failed off keeps recovery in place. An external hold belongs to another tool;
turn that tool off first. `lidwise off --force` is an explicit global override.
Other `caffeinate` assertions or macOS settings can still prevent some forms of sleep.

Do not delete the app, permission rule, or recovery state while restoration is failing.
The uninstaller stops when it cannot verify the required state.

## The menu icon disappeared

Use the configured global shortcut to open the menu. The app retains its notch
placement controls. Check whether another menu-bar organizer hides the icon.

## Activity appears quiet

Quiet means recent activity was not observed. It does not mean the job completed.
Use the agent or job's own terminal to verify its state. Notifications are opt-in.

## Network is unavailable

Use `lidwise netdiag` and the [network guide](NETWORK.md). The app does not restore
DHCP by overwriting network configuration and does not turn Wi-Fi back on for you.

## Before reporting a bug

Include the app version, macOS version, processor family, power source, attached
displays, the visible error, and relevant `doctor` output. Review diagnostics for
private paths or job names before sharing. Never include agent transcripts or secrets.
