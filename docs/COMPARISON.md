# Alternatives and positioning

Snapshot from the September 15, 2026 launch review. Features below are documented
claims, not independent hardware tests. This is a bounded search; it cannot establish
that every competing project has been found.

| Project | In the pre-review README? | Documented capabilities relevant here | What to learn |
|---|---|---|---|
| [Keepresso](https://github.com/gyorgysh/keepresso) | No | Broad agent hooks, per-session activity, manual/timed sessions, end warnings, scheduled AI wake, setup flow, diagnostics, Shortcuts, and updates. Latest release v1.25.0 was September 14. | My assessment: closest feature competitor. Adopt reliable status and simple duration controls; avoid matching its entire toolkit. |
| [Lidless](https://github.com/nghialuong/Lidless) | Yes | Authenticated helper architecture, adjustable time/battery/charging policies, notarized DMG, Sparkle updates, shared tested policy logic. | Useful benchmark for installation and lifecycle. Its current README does not document agent mode; do not present the old UI observation as a newly verified fact. |
| [Hold My Lid](https://holdmylid.app/) | No | Agent hooks, broader provider support, quick pause, configurable battery/AC behavior, Homebrew install. | Explicit signals beat inference. Its closed-lid claims and bag-use marketing were not validated here; do not copy those claims. |
| [goguma](https://github.com/junnam586/goguma) | No | Scheduled wake, job history, command-scoped holds, agent integrations, CLI plus service-backed viewer. | Stronger for “wake for a future job.” That is a separate product expansion, not a launch requirement. |
| [LidAwake by NeoSpecies](https://github.com/NeoSpecies/LidAwake/blob/main/README.en.md) | No | Published lid-close measurement method, reproducible probe, JSON status, diagnostics, event-driven architecture and idle-exit claim. | Copy the evidence standard. Distribution docs disclose unsigned/unnotarized packaging; latest release metadata had no attached assets, so it is an engineering benchmark rather than proven distribution polish. |
| [Lid Awake by thuongtin](https://github.com/thuongtin/lid-awake) | No | Signed/notarized releases, signed update feed, explicit helper trust boundary, setup/security documentation. | Clear capability reporting. Current public builds are Apple Silicon only. |
| [StayUp](https://github.com/NongKnot/StayUp) | No | Opt-in activity receipts, onboarding, helper coverage indicators, update controls, remote GUI support. | Say when closed-lid coverage is unavailable. Its broader toolkit is not necessary here. |
| [Amphetamine](https://apps.apple.com/us/app/amphetamine/id937984704) | Yes | Mature trigger system, broad session controls, familiar App Store distribution. | Keep comparisons precise: its closed-display mode exists and documents power-transition caveats and an optional script/authentication path. |
| [Lungo](https://sindresorhus.com/lungo) | Yes | Focused interaction, durations and automation through URL schemes/Shortcuts. | Simplicity benchmark. Its own FAQ excludes standalone closed-lid use without charger and external display. |
| [KeepingYouAwake](https://github.com/newmarcel/KeepingYouAwake) | Yes | Small open-source utility, simple timed sessions and established distribution. | Scope discipline. Its own FAQ explicitly excludes closed-lid operation. |
| [Tamp](https://github.com/vyskoczilova/tamp) | No | Shows external sleep assertions alongside its own sessions; CLI. | Explain who is keeping the Mac awake. Adjacent tool, not established standalone clamshell support. |
| [macowl](https://github.com/rgcsekaraa/macowl) | No | Focused menu utility and explicit recovery prompt for a machine left awake. | Transparent restart/recovery experience. |

Additional direct alternatives found: [LidAwake by TurboKach](https://github.com/TurboKach/LidAwake), [LidAwake-Mac by deezeddd](https://github.com/deezeddd/LidAwake-Mac), [Insomniac by Vatsal057](https://github.com/Vatsal057/Insomniac), and [vigil](https://github.com/dbuskariol/vigil). These confirm that lid-close toggling itself is crowded. This is a bounded search, not a claim that no further projects exist.

**Positioning:** “Keep this Mac awake for a bounded session you control, with visible recovery.” Your combination of manual authority, CLI access, and optional monitoring suits interrupted and multi-job work. Free/open source, agent support, and Wi-Fi features are each available elsewhere; none alone establishes an advantage. Keepresso now includes network diagnostics and user-invoked recovery, so do not imply that all competing apps lack networking tools.


For this release, prioritize trustworthy state, bounded sessions, setup diagnostics,
and honest activity. Scheduled wake, automatic agent-owned sessions, fan control,
remote displays, and a general trigger engine remain separate product decisions.
