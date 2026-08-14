# Release checklist

Unsigned community builds can be published with a clear Gatekeeper warning.
Complete this checklist before describing a build as production-signed,
notarized, or broadly hardware-tested.

## Production release gate

- [ ] Choose the final repository owner and security-contact URL.
- [ ] Review the MIT license and copyright line.
- [ ] Test on at least one Intel Mac and one Apple Silicon Mac.
- [ ] Test on battery, AC power, reboot, logout/login, and Wi-Fi loss.
- [ ] Confirm normal lid-close sleep after every failure path.
- [ ] Configure a Developer ID Application certificate.
- [ ] Configure a `notarytool` keychain profile.
- [ ] Sign, notarize, staple, and assess the app.
- [ ] Inspect the packaged archive and verify its SHA-256 file.
- [ ] Publish release notes that repeat the heat and enclosed-bag warning.

## Local verification

```bash
./scripts/check.sh
./scripts/package.sh
```

## Signing and notarization

Store notarization credentials in the macOS Keychain, not in this repository:

```bash
xcrun notarytool store-credentials closed-lid-awake-notary
```

Then run:

```bash
SIGNING_IDENTITY="Developer ID Application: Example (TEAMID)" \
NOTARY_PROFILE="closed-lid-awake-notary" \
./scripts/notarize.sh
```

The script signs with the hardened runtime, submits to Apple, staples the
ticket, runs Gatekeeper assessment, and packages the stapled app.

## Artifact inspection

```bash
codesign -dv --verbose=4 "dist/Closed-Lid Awake.app"
spctl --assess --type execute --verbose=2 "dist/Closed-Lid Awake.app"
(cd dist && shasum -a 256 -c *.sha256)
```
