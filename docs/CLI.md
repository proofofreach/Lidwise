# Command line

The app and `vibecaf` share one manually owned session.

| Command | Behavior |
|---|---|
| `vibecaf on` | Start using the saved duration, up to six hours. |
| `vibecaf on --for 1800` | Start a 30-minute session. Existing sessions keep their deadline. |
| `vibecaf off` | Restore sleep for this app's session, with readback verification. |
| `vibecaf off --force` | Explicitly clear the global sleep hold, including another tool's hold. |
| `vibecaf toggle` | Serialize the operation and preserve external ownership. |
| `vibecaf status --json` | Versioned status; `off`, `owned-on`, `external-on`, or `unknown`. |
| `vibecaf doctor` | Read-only setup diagnostics. |
| `vibecaf config get --json` | Read saved settings. |
| `vibecaf config set duration 3600` | Default future sessions to one hour. |
| `vibecaf config set recovery off` | Disable network monitoring. Compatibility key; no automatic network writes. |
| `vibecaf config set notifications on` | Opt in to agent notifications. |

The system-wide `SleepDisabled` flag has no operating-system ownership token.
The app records its own session and will not adopt a preexisting hold. Two power
utilities changing the flag during one session cannot be perfectly distinguished;
avoid concurrent controllers.

## Optional activity

`vibecaf agents` reports locally observed Claude Code and Codex activity. Browser
native-message hosts, MCP servers, and child-session logs are excluded from
independent session counts. Working and quiet are activity estimates. Finished
requires an explicit terminal event. Transcripts can be incomplete or change format.

Registered goals provide explicit job state. For example:

```bash
vibecaf goal add "build" --pid 12345 --stale-after 300
vibecaf goal touch "build" "Still running"
vibecaf goal complete "build" "Finished"
vibecaf goal fail "build" "Exit code 1"
vibecaf goal remove "build"
vibecaf goals --refresh
vibecaf agents --refresh
vibecaf agents --summary
```

`goal add` also accepts `--activity-file PATH`; `goal restart` accepts the same options.
Replace the sample PID with the actual job PID. Neither automatic activity nor registered goals
owns the sleep session. A job can finish while the Mac remains awake, or the safety
deadline can end the session while a job still runs.

Machine clients should validate `schema_version` before reading JSON. Treat missing,
malformed, stale, or failed status as unavailable; never infer off from empty output.
