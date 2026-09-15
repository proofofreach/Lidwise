# Hardware validation record

Status: **pending for the 1.2 candidate**. The development host is Apple Silicon,
macOS 26.6.2. Daily use of an earlier build does not certify this changed candidate.
No install, power-setting change, logout, reboot, or network mutation was performed
on the daily-use installation during implementation.

For each run record: exact source commit, ZIP SHA-256, signing status, Mac model and
CPU, macOS version, battery/AC, displays, network configuration, expected result,
observed result, elapsed recovery time, and pass/fail. Keep private machine identifiers
and network names out of committed evidence.

| Case | Evidence |
|---|---|
| AC/battery lid close without external display | Pending |
| End-of-session normal lid sleep | Pending |
| Power transition and battery floor | Pending |
| Timer expiry and activation interruption | Pending |
| Kill/freeze app and guard independently | Pending |
| Logout/login and reboot | Pending |
| Missing privilege or thermal helper | Pending |
| DHCP/custom client ID/static/VPN/Ethernet/portal/radio-off | Pending |
| Fresh install, failed upgrade, incomplete uninstall | Pending |
| Live keyboard/VoiceOver/contrast/reduced-motion/notch | Pending |
| Intel and minimum supported macOS | Pending |

Run disruptive cases on a dedicated test account or device with work saved and an
accessible recovery terminal. Do not close the lid in a bag or obstruct ventilation.
Do not report a simulated low-battery or mock launchd test as a hardware result.
