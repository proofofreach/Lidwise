# Lidwise product

## Audience and job

Lidwise serves MacBook users running long local work: coding agents, builds,
transfers and registered jobs. They choose a timed session or Full On with no timer. The
Mac should remain awake with its lid closed on a hard, ventilated surface.

## Product promise

Keep your Mac awake for a session you control, with a clear duration mode and visible
sleep restoration. Report observed state and capability. Never infer successful
restoration from a requested action, job completion from inactivity, or thermal
safety from software checks.

## Accepted behavior

- One manually owned session shared by the native menu app and CLI.
- Timed sessions have a maximum six hours from original session start; repeated on commands do not
  extend it. An explicit extension changes a still-active session within that cap. Full On has no deadline and runs until turned off or a safety cutoff.
- Battery, charging and thermal policy can end a session before its deadline.
- Optional agent activity and hook signals report work; they do not own sleep.
- An external power hold remains external. Unknown state remains unknown.
- Quit can leave the owned session and independent recovery running. Turn off
  and quit verifies that this app released its override first.
- A local session history explains the end and restoration result. It does not
  certify that a particular job completed or that the machine slept continuously.
- Guided lid verification measures the current configuration. It does not change
  power policy or certify other Macs, macOS versions or future runs.

## Identity and distribution

Preserve the compact native dark panel and accepted controls in DESIGN.md.
Use progressive disclosure for occasional controls and optional activity. Keep
the community route free, ad hoc signed and unnotarized unless the user changes
that decision. Preserve the rename's compatibility identifiers and state paths.

## Current implementation scope

Expiry warning and explicit extension; last-session history; saved power policy;
explicit supported attention/completion events; guided local verification. Setup
and removal should explain their progress and preserve unrelated configuration.
See docs/FEATURE_IMPLEMENTATION.md for the shared contract and verification.

## Outside this release

Automatic agent-owned sessions, command-scoped holds, scheduled wake, general
trigger rules, virtual displays, fan control, automatic Wi-Fi repair, cloud
accounts, paid plans and fleet management.

## Evidence needed

The existing hardware record covers specific earlier candidate revisions. New
feature checks must distinguish fixture/build evidence from real lid, power,
logout, reboot, clean-download and accessibility observations. Public claims must
match the actual downloadable version.
