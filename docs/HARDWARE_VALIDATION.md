# Hardware validation record

Tested September 15, 2026 on Mac16,1 (Apple Silicon/arm64), macOS 26.6.2.
User authorized local installation and supervised lid/power testing. These results
cover this Mac; Intel and macOS 13 execution remain unverified.

## Candidate identity

- Power tests: source `aa9aacafda0e6eabb33dc6cd22e79b7e61981807`.
- Its ZIP SHA-256: `feb050982cdba27e8938d065f3fca57c3a19832e363321653ed90807de5ebc26`.
- Normal lid-sleep test: parser follow-up `efadb3b839fbcdfeb0d3bab01a073360b97d5ce0`, with unchanged power policy.
- Shared-monitor runtime test: `79f33b524823bc1f7060d096d6a1487c4f8f96b9`.
- These were universal, ad hoc signed community candidates, not notarized.
- Raw local observations and rollback copies are retained in the ignored local-test directory. `dist/LOCAL_TEST_RESULTS.md` records those paths; this table summarizes the evidence without publishing private session data.

| Case | Evidence |
|---|---|
| AC lid close | 75 closed-lid samples spanning 180.22 seconds; maximum gap 2.51 seconds. Same owned session and recovery ready throughout. User confirmed the monitor was disconnected for at least one minute. Display absence in that interval is user-reported. |
| Battery lid close | 78 closed-lid battery samples spanning 191.25 seconds; maximum gap 2.61 seconds. Recovery ready throughout. User reported completing the instructed monitor-disconnected test; display absence was not continuously instrumented. |
| Normal lid sleep after off | macOS logged Clamshell Sleep at 14:46:00 CDT, background DarkWake at 14:46:03, Maintenance Sleep at 14:46:20 and lid/HID wake at 14:46:27. Current phase off. This was not uninterrupted deep sleep. |
| Power transitions | AC → Battery → AC preserved the same session and deadline. Battery remained 100%; the low-battery floor was not exercised. |
| Timer expiry | Real 30-second session restored `SleepDisabled 0` automatically by the observation at 56.2 seconds, approximately 26 seconds after expiry. Expiry is checked periodically, not an exact-time wake/sleep scheduler. |
| Guard crash | Killed only the verified session guard. Readiness immediately became false; independent guardian restored normal sleep about 180.1 seconds later, before the 300-second session deadline. |
| Local upgrade | Previous app backed up; native administrator authentication completed install. One menu app ran, installed source revision and nested signatures matched, system guardian ran as the user, restoration permission and thermal helper available. |
| State migration | Existing owned state folder was 0755. Activation initialized it as 0700; state/runtime diagnostics passed afterward. |
| Shared monitoring worker | Installed `79f33b5`; four samples over about 32 seconds showed one observer and no separate network worker, with network online. Guardian readiness became current after its first heartbeat. Explicit off restored normal sleep; only the menu app and recovery guardian remained among persistent app workers. |
| Frozen app/guard and interrupted activation | Isolated regressions pass; real-device cases pending. |
| Logout/login and reboot | Pending. |
| Missing privilege or thermal helper | Isolated regressions pass; real-device fault injection pending. |
| Static/custom-DHCP/VPN/Ethernet/portal/radio-off | Read-only loop regressions pass; full real-network matrix pending. No configuration-changing recovery remains. |
| Fresh install, failed upgrade, incomplete uninstall | Isolated lifecycle tests pass; clean-device and real failure cases pending. |
| Live keyboard/VoiceOver/contrast/reduced-motion/notch | Pending. Computer-use inventory did not expose the menu app. User operated the primary control and copied diagnostics. |
| Quarantined download / Open Anyway | Pending. Local installation does not establish the downloaded-app experience. |
| Intel and minimum supported macOS | Pending. Universal compilation is not runtime certification. |

The installed candidate is for local testing. No release was published. Do not mark
remaining gates complete from these results. Disruptive remaining tests require a
supervised window with work saved and a recovery terminal available. Keep the Mac
on a hard, ventilated surface; never run it awake in a closed bag.

## Feature revision: read-only probe smoke test

On September 15, the new native lid probe ran for 15.00 seconds on Mac16,1,
macOS 26.6.2 (25G83), with the lid open. It collected 31 samples, registered
lid notifications, and reported **inconclusive** because no closed-lid signal
was observed. The maximum sampling gap was 0.505 seconds; the measured clock
difference was below a microsecond. No power settings or installed app changed.

This checks the live read-only measurement path and its refusal to pass without
lid evidence. It does not validate the new revision's closed-lid operation,
extension, AC-only cutoff, expiry notification delivery, or recovery behavior on
real hardware. Synthetic measurement and isolated lifecycle tests cover those
code paths separately. The earlier hardware rows remain tied to their listed
source revisions.
