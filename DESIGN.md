# Lidwise design

## Product intent

Lidwise is a macOS menu bar utility for a manual awake session, timed or Full On. It serves people who leave long local jobs running while a MacBook lid is closed. The app reports verified helper state. Agent and goal data is observation only.

## Accepted identity

- Keep the compact, dark native panel. It is a quiet utility, not a dashboard.
- Use the system font and SF Symbols for a familiar macOS feel.
- Use deep navy surfaces, a blue action accent, mint for verified active state, amber for attention, and coral for faults.
- Keep one primary session toggle in the status card. The global shortcut invokes the same action.
- Put routine status first. Put settings, diagnostics, help, and quit actions behind clear disclosure.

## Tokens

| Role | Value |
|---|---|
| Canvas | `#0E111F` |
| Bay | `#131729` |
| Rail | `#111422` |
| Primary text | `#EBF0FF` |
| Secondary text | `#9EA8D1` |
| Accent | `#648CFF` |
| Verified | `#63D9B0` |
| Attention | `#F2B051` |
| Fault | `#FF757A` |
| Panel width | 408 pt |
| Outer radius | 18 pt |
| Content inset | 18 pt |

## State language

- **Off:** normal macOS sleep applies.
- **On:** show the verified end clock and remaining time, or **Full On · no timer**.
- **External hold:** another tool is preventing sleep; leave it unchanged.
- **Unknown:** disable the main control and offer **Check setup**.
- **Pending:** disable changing controls and name the operation in progress.
- **Fault:** wrap the helper message. Do not infer success from the requested action.

Never use “Protected” as a result of a click. “Recovery ready” is permitted only when the helper reports verified recovery capability.

## Interaction rules

- Session durations are fixed at 30 minutes, 1 hour, 2 hours, 6 hours, and **Full On** (no timer).
- Changing duration while a session runs changes the next session. It does not extend the current deadline.
- Show **Add 30 minutes** only while the helper reports that the owned session can be extended. Keep the six-hour total cap visible in the action detail.
- Battery floor and AC requirements apply to the next session. Keep them in Settings and continue to show the active session's actual policy in the status card.
- Activity is collapsed by default. Hide empty providers and empty goals. Use only helper-supplied `working`, `waiting`, `quiet`, `finished`, and `failed` counts. Surface the combined waiting and failed count as attention, without inferring success.
- Keep session history private and bounded. Use a separate readable detail window. A failed restoration record describes the last restoration attempt because the session can still be active.
- Agent integration setup is optional. Show helper-reported provider support, current setup, and an exact configuration preview before installation. Never imply that a provider supports signals it does not report.
- **Test closed-lid behavior** opens a separate, non-modal window. Explain the ventilated-surface procedure, keep the menu controls usable, show progress, and provide a selectable, copyable result. An inconclusive measurement is not a pass or failure.
- **Network monitoring** controls read-only probes. It does not promise automatic repair or change network settings.
- **Quit menu bar app** leaves an owned manual session running until its deadline or, for Full On, until explicitly stopped or a safety cutoff.
- **Turn off and quit** first verifies normal sleep restoration. It stays disabled when no app-owned session is active.
- Login launch and session-at-login form one dependency. Session-at-login is unavailable until menu bar launch is enabled.

## Accessibility

- Keep native controls and keyboard operation.
- Give the main toggle an action-specific label and hint.
- Do not communicate state with color alone. Pair each color with text and an SF Symbol.
- Wrap fault text and keep diagnostics selectable and copyable.
- Respect system control contrast and reduced-motion behavior. The only transient motion is the system HUD fade.
