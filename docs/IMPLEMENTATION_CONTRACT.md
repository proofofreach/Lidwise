# Launch implementation contract

This is the shared contract for concurrent implementation of `LAUNCH_REVIEW.md`.
The original review is a dated audit. Completion evidence will be recorded separately.

## Ownership

- Core agent: `bin/lidwise`, new `lib/lidwise/session.sh` if useful, safety/ownership/config/JSON tests.
- Network/observation agent: `lib/lidwise/network.sh`, `lib/lidwise/observation.sh`, `bin/lidwise-agent-scan`, optional new `src/AgentScan.swift`, network/agent/goal tests.
- UI agent: `src/Lidwise.swift`, any new UI Swift source and UI tests, `DESIGN.md`.
- Coordinator: build/package/install/uninstall/guardian scripts, release verification and lifecycle tests, product/user documentation, integration.

Do not edit another owner's files without coordination. Do not install over the daily-use app, change real power/network/privilege state, publish, or run paid GitHub features during development. System calls in regression tests must be stubbed. Preserve the existing scanner fix that excludes browser native-message hosts.

## CLI

- `on [--for SECONDS]`: idempotent owned session, default six hours, duration 1–21600 seconds; no implicit extension or adoption of another tool's hold.
- `off`: restore only this tool's owned session. Explicit `off --force` is the user's override for external power state. Verify the result.
- `toggle`: no overlap across callers; preserve external-on state and explain it.
- `status [--json] [--net]`: versioned machine output or human output. Unknown is never off. Core power status must not depend on optional observation success.
- `config get --json`; `config set duration SECONDS`; `config set recovery on|off`; `config set notifications on|off`. Settings persist locally and are used by future sessions; recovery and notifications should apply to the current session as well.
- `doctor`: read-only, copyable setup diagnostics. No privileged or network mutation.
- Existing goal, agents, netlog and netdiag commands remain available.

## Status JSON v1

Required keys (nullable fields are JSON null when unavailable):

```json
{
  "schema_version": 1,
  "phase": "off",
  "session_id": null,
  "started_at": null,
  "deadline": null,
  "remaining_seconds": null,
  "duration_seconds": 21600,
  "battery_floor": 20,
  "power_source": "AC",
  "battery_percent": 100,
  "thermal": "nominal",
  "guard_running": false,
  "guardian_running": false,
  "recovery_ready": false,
  "issues": [],
  "network_state": "unknown",
  "network_detail": "Not checked",
  "network_recovery": true,
  "agent_notifications": false,
  "agents": {
    "claude": {"working": 0, "quiet": 0, "finished": 0},
    "codex": {"working": 0, "quiet": 0, "finished": 0}
  },
  "goals": {"active": 0, "stalled": 0, "completed": 0, "failed": 0},
  "observed_at": 0
}
```

Optional `default_duration_seconds` carries the configured duration for the next session; `duration_seconds` remains the active session policy when owned. Consumers ignore unknown object keys. Additive optional fields do not change the schema version. `network_recovery` remains the saved monitoring setting for compatibility. Optional `network_recovery_available` reports automatic repair capability and is false in this candidate; read-only monitoring remains available.

`phase` is `off | owned-on | external-on | unknown`. UI pending state is separate. Unknown/missing/malformed schema must fail explicitly. Deadlines and battery policy come from the actual owned session. `recovery_ready` means verified required capabilities, not merely an existing launchd label. `issues` supplies readable recovery faults.

Observation module exports `agents_json` (the agents object above), `goals_json`, existing human summary functions, and `observation_loop` for optional scanning separated from safety. Quiet files are never inferred finished. Network module exports `network_status_token`, `cheap_net` (human detail), and existing start/stop functions. Cached timestamps are validated before arithmetic. Shared helpers (field access, secure runtime and PID identity) are owned by core; coordinate their signatures before use.

## Build paths

- Bundled shell entry: `Contents/Resources/lidwise`.
- Bundled modules: `Contents/Resources/lib/lidwise/*.sh`.
- Required native helpers: `Contents/Helpers/lidwise-thermal`, `lidwise-agent-scan-core`, and `lidwise-lid-probe`.
- Source-checkout native helpers: `.build/helpers/` (built before shell tests).
- Coordinator changes the build to allow isolated build/output directories so concurrent checks cannot erase another agent's work.

## UI

Preserve the accepted dark menu panel and hotkey. One primary control, pending/error/external states, bounded presets, readable safety, optional Activity disclosure, coherent login controls, recovery/notification settings, diagnostics, About/version/support/update route, and explicit Quit choices. Use typed subprocess results, timeouts, fully drained output streams, serial mutation, and stale-refresh suppression. No safety assertion follows solely from the requested action.

## Verification

All review acceptance scenarios need evidence. Code/unit/stub tests do not certify actual lid, logout, reboot, thermal, or network-hardware behavior. Keep real-device gates pending until observed. Signed artifact checks must inspect every Mach-O and the extracted candidate; no ad hoc executable in a production candidate. Never hide an unmet gate by weakening checks or declaring untested platforms supported.
