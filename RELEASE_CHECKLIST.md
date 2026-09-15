# Release gates

1.2.0 is an unreleased community candidate. The user selected free GitHub distribution
without Developer ID signing or notarization. A development archive is not a verified
community release.
Do not publish or recommend it for unattended use until the gates below have evidence.

## Source and local verification

- [x] Independent implementation review completed; findings fixed or adjudicated with evidence.
- [x] `./scripts/check.sh` passes, including the Desktop parser and off-state activity follow-ups.
- [x] Core failure/concurrency, observer, network, UI, and installer regression tests pass.
- [x] Freeze the reviewed source commit, including the existing scanner correction (see candidate `CLASourceRevision`).
- [ ] Version, changelog, source manifest, tag, release notes, and asset agree.
- [x] Repository owner and private security-report route verified: proofofreach/ClosedLidAwake.
- [x] MIT license is present; retain contributor attribution.

## Real-device evidence

Record the exact build hash, model/CPU, macOS version, and observation in
`docs/HARDWARE_VALIDATION.md`. Compilation and mocks do not satisfy these checks.

- [ ] Lid closed on AC and battery, with no external display: work continues, then normal sleep returns.
- [ ] Unplug/replug and battery floor: policy is honored across power transitions.
- [ ] Timer and interrupted activation: deadline or rollback restores normal sleep.
- [ ] App and guard killed/frozen separately: recovery occurs within its specified bound.
- [ ] Logout/login and reboot: no unmanaged persistent sleep block; startup preference is honored.
- [ ] Missing permission and thermal helper: activation refuses unsafe setup; UI remains truthful.
- [ ] Static and DHCP/custom-client-ID Wi-Fi, Ethernet, VPN, portal, radio-off: settings remain unchanged.
- [ ] Clean install, failed upgrade, partial uninstall: recovery remains available on failure.
- [ ] Live menu keyboard, shortcut, VoiceOver, increased contrast, reduced motion, notch placement, and long errors checked.
- [ ] Test each advertised processor and OS configuration, or narrow claims to the tested matrix.

## Community distribution (selected)

- [x] Validate all three universal native executables and the extracted archive with `verify-release.sh community`.
- [ ] Test a quarantined download and Apple’s per-app Open Anyway flow on a clean supported Mac.
- [ ] Label the GitHub release ad hoc signed and not notarized; include first-launch instructions.
- [ ] Publish one verified asset and checksum; ensure `/releases/latest` resolves to it.
- [ ] Include ventilation/bag warning and exact tested-platform limits in release notes.

Signing is optional for this route. All source, review, lifecycle and real-device
safety gates above still apply. No Apple membership purchase is authorized or required.

## Optional future notarized distribution

- [ ] Use a Developer ID Application identity and an existing `notarytool` keychain profile.
- [ ] Sign every native executable with the same identity, hardened runtime, and timestamp.
- [ ] Notarize, staple, and assess the final app.
- [ ] Run `verify-release.sh production` on the final extracted ZIP and checksum.
- [ ] Test a quarantined download on a clean supported Mac without developer tools.
- [ ] Publish one verified asset and checksum; ensure `/releases/latest` resolves to it.
- [ ] Include ventilation/bag warning and exact tested-platform limits in release notes.

## Commands

```bash
./scripts/check.sh
RELEASE_MODE=community ./scripts/package.sh
./scripts/verify-release.sh community dist/Closed-Lid-Awake-1.2.0-macos-universal.zip
```

After committing the reviewed source and configuring credentials in Keychain:

```bash
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="closed-lid-awake-notary" ./scripts/notarize.sh
```

`notarize.sh` requires a clean committed tree, runs local checks, builds, submits,
staples, packages, and validates the extracted production artifact. Never commit
signing credentials. Do not use GitHub metered services without explicit approval;
these checks run locally.
