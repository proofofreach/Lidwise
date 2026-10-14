# Command line

The app and `lidwise` share one manually owned session.

| Command | Behavior |
|---|---|
| `lidwise on` | Start using the saved duration or Full On (no timer). |
| `lidwise on --for 0` | Start Full On with no timer. Battery, AC, thermal, and recovery cutoffs still apply. |
| `lidwise on --for 1800` | Start a 30-minute session. Existing sessions keep their deadline. |
| `lidwise extend --by 1800` | Explicitly add 30 minutes to an owned, unexpired session, within six hours of its original start. |
| `lidwise off` | Restore sleep for this app's session, with readback verification. |
| `lidwise off --force` | Explicitly clear the global sleep hold, including another tool's hold. |
| `lidwise toggle` | Serialize the operation and preserve external ownership. |
| `lidwise status --json` | Versioned status; `off`, `owned-on`, `external-on`, or `unknown`. |
| `lidwise doctor` | Read-only setup diagnostics. |
| `lidwise config get --json` | Read saved settings. |
| `lidwise config set duration 0` | Default future sessions to Full On (no timer). |
| `lidwise config set duration 3600` | Default future sessions to one hour. |
| `lidwise config set recovery off` | Disable network monitoring. Compatibility key; no automatic network writes. |
| `lidwise config set notifications on` | Opt in to agent notifications. |
| `lidwise config set battery-floor 30` | Save a 30% battery floor for the next session; accepts 1–100. |
| `lidwise config set require-ac on` | Require connected power for the next session. |
| `lidwise history --json` | Read bounded local session history and restoration results. |
| `lidwise verify --expect awake --seconds 60 --json` | Measure lid state and sleep for one minute without changing power settings. |

## Session endings and power policy

An explicit extension preserves the session's start time and power policy. It
cannot extend an expired or external session, or exceed the six-hour total cap.
An over-limit request fails without changing the deadline. Choose a shorter
initial duration if you want room to extend it later.

The guard warns once when a session enters its last five minutes. A local banner
may not be visible while the lid is closed. The warning does not extend the
session, delay a cutoff, or guarantee notification delivery. An explicit extension
can rearm a warning for its new deadline.

Battery-floor and charging-only changes apply to the **next session**. The active
session keeps the policy shown in status. The default floor is 20%; charging-only
defaults off. A charging-only session releases its hold if the power adapter is
disconnected. Battery and thermal policy always remain independent of agent work.

JSON status keeps schema version 1 and adds optional fields for saved power
defaults, current charging-only policy, extension availability and the latest
session record. Old clients can ignore additive fields.

## Session history

`lidwise history` shows recent session records; add `--json` for structured
output. History contains at most 20 entries with time, end reason, power/battery
measurements where available, and verified, failed or unknown restoration.
It does not store transcript text or job names.

“Verified” means the app read back its cleared sleep override. It does not mean
that the Mac slept immediately, stayed asleep, or completed a job. Failed
restoration must remain visible until recovery succeeds. Corrupt history must
not prevent sleep restoration.

## Guided lid verification

Use **Test closed-lid behavior** in the app's diagnostics, or run:

```bash
lidwise verify --expect awake --seconds 60
```

Start the session you intend to test first. Close the lid for at least ten seconds
and reopen it during the measurement window. Disconnect external displays if you
want to test standalone operation. Keep the Mac on a hard, ventilated surface.
The probe does not start a session, alter a deadline, or schedule a wake.

To test normal lid sleep, turn awake mode off, check that no other utility is
holding the Mac awake, then run:

```bash
lidwise verify --expect sleep --seconds 60
```

Actual sleep suspends the probe. Reopen the lid to receive its result. The probe
compares continuous and awake monotonic clocks, records lid signals, and reports
**passed**, **failed**, or **inconclusive**. An awake result needs at least ten
seconds of closed-lid coverage without missing lid evidence or interrupted
sampling. A sleep result needs a measured sleep interval that began with the lid
closed. The result describes only this run on the reported Mac and macOS version.
It does not prove continuous network access or uninterrupted sleep.

Durations are limited to 15–120 seconds. Add `--json` for an exportable result;
a completed measurement returns exit code 0 even when its result is failed or
inconclusive. Invalid arguments return 2. This lets callers distinguish a measured
failure from a helper that could not run.

The system-wide `SleepDisabled` flag has no operating-system ownership token.
The app records its own session and will not adopt a preexisting hold. Two power
utilities changing the flag during one session cannot be perfectly distinguished;
avoid concurrent controllers.

## Optional activity

`lidwise agents` reports locally observed Claude Code and Codex activity. Browser
native-message hosts, MCP servers, and child-session logs are excluded from
independent session counts. Working and quiet are activity estimates. Finished
requires an explicit terminal event. Transcripts can be incomplete or change format.

### Claude Code lifecycle signals

Open **Agent integrations** to inspect and preview the optional Claude Code setup,
or use:

```bash
lidwise hooks status --json
lidwise hooks preview claude --json
lidwise hooks install claude
lidwise hooks remove claude
```

Preview returns the old and proposed JSON settings. Installation adds Lidwise's
commands to the user's Claude Code settings and preserves unrelated hooks. Removal
removes only Lidwise's commands. Configure the installed app, so these commands
refer to a stable executable path. Restart Claude Code after changing setup.

Prompt submission reports working. Supported permission/elicitation notifications
report waiting. Stop reports a finished turn only when the event has no background
tasks or session crons; StopFailure reports failed. These signals describe an
agent turn, not whether a project or job succeeded. The activity display can
still fall back to recent local logs. Hook events expire instead of remaining
current indefinitely. Notifications remain opt-in.

Missing task-registry information cannot establish completion. Later meaningful
activity can supersede an older signal; ambiguous timing preserves the last known
signal until newer evidence arrives. An observation failure does not block a
Claude prompt or force the agent to continue.

The adapter follows the [Claude Code hook reference](https://code.claude.com/docs/en/hooks).
Older Claude Code versions may not expose every event.

Automatic Codex hook setup is not implemented. Codex completion remains observed
from local logs; this integration does not provide a Codex waiting signal. Existing
Codex notification commands remain unchanged.

The uninstaller removes installed Lidwise hooks before deleting the app. If hook
removal fails, it retains the app and recovery setup and reports the error.

Registered goals provide explicit job state. For example:

```bash
lidwise goal add "build" --pid 12345 --stale-after 300
lidwise goal touch "build" "Still running"
lidwise goal complete "build" "Finished"
lidwise goal fail "build" "Exit code 1"
lidwise goal remove "build"
lidwise goals --refresh
lidwise agents --refresh
lidwise agents --summary
```

`goal add` also accepts `--activity-file PATH`; `goal restart` accepts the same options.
Replace the sample PID with the actual job PID. Neither automatic activity nor registered goals
owns the sleep session. A job can finish while the Mac remains awake, or the safety
deadline can end the session while a job still runs.

Machine clients should validate `schema_version` before reading JSON. Treat missing,
malformed, stale, or failed status as unavailable; never infer off from empty output.
