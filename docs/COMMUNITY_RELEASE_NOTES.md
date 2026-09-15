# 1.2.0 community release notes — draft

**Not published. Hardware validation remains pending.**

Lidwise adds bounded manual awake sessions, clearer ownership and recovery
status, duration presets, and optional local Claude Code/Codex activity monitoring.
Failed commands now refresh actual state, and the menu adapts to longer fault messages.

The candidate also adds explicit session extension, an advance expiry warning,
saved next-session battery/charging policy, local session history, supported agent
attention events, and a guided read-only lid test. These additions need their own
real-device checks; earlier hardware observations do not certify this revision.

This build is free, ad hoc signed and **not notarized by Apple**. No Apple Developer
membership is required. Download the ZIP and matching `.sha256` file together,
verify the checksum, extract the ZIP, and run `./install.sh` from its folder.
Administrator authorization installs the recovery job and narrow sleep-control rule.

If macOS blocks opening the app, review the source and follow
[Apple’s per-app Open Anyway procedure](https://support.apple.com/en-us/102445).
Managed Macs may prohibit this exception.

Network monitoring is read-only and preserves existing configuration. Agent activity
never controls sleep, and quiet activity does not mean a job has completed.

Keep the Mac on a hard, ventilated surface. Never run it awake in a closed bag.
Software checks do not guarantee thermal safety or keep a particular job alive.

## Evidence to fill before publication

- Reviewed source commit and final ZIP SHA-256.
- Exact tested Mac models, CPU architectures and macOS versions.
- Real lid, power, recovery, logout/reboot and install results.
- Quarantined download and first-launch result.

The binaries contain arm64 and x86_64 code targeting macOS 13. That is build
coverage, not certified hardware compatibility. The development host is Apple
Silicon running macOS 26.6.2. Publish only the platform support demonstrated by
[the hardware record](HARDWARE_VALIDATION.md).
