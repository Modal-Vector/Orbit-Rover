---
title: CLI Reference
last_updated: 2026-03-11
---

[← Back to Index](index.md)

# CLI Reference

## orbit dashboard

Live-updating TUI dashboard showing missions, components, sensors, and gates.

```bash
# Start live dashboard (refreshes every 2s)
orbit dashboard

# Custom refresh interval
orbit dashboard --refresh 5

# Render once and exit (useful for CI/scripting)
orbit dashboard --once

# Plain text (no gum styling)
orbit dashboard --no-color
```

Requires `gum` (charmbracelet) for styled output. Falls back to plain text
automatically when gum is not installed. Install gum:
`brew install charmbracelet/tap/gum` (macOS) or see https://github.com/charmbracelet/gum.

Keyboard: **r** = refresh now, **q** = quit.

---

All commands are invoked as `./orbit <command> [options]`.

Global options:

| Option | Description |
|--------|-------------|
| `--log-level <level>` | Set log verbosity (debug, info, warn, error) |
| `--help` | Show usage information |

## orbit init

Bootstraps a new Orbit project with full directory scaffolding.

```bash
orbit init <project-name>
```

Creates: `orbit.yaml`, `CLAUDE.md`, `RISK-REGISTRY.md`, `components/`,
`missions/`, `modules/`, `prompts/`, `scripts/`, `tools/`, and the `.orbit/`
state directory tree.

## orbit doctor

Checks system dependencies and reports their status.

```bash
orbit doctor
```

**Critical** (exit 1 if missing): bash 4+, jq

**Optional** (warning if missing): python3, yq, cron, claude, opencode,
ollama, inotifywait, gum

## orbit run

Executes a single component or module outside of mission context.

```bash
# Run a component
orbit run <component-name>

# Run a module with parameters
orbit run <module-name> --params '{"key":"value"}'
```

Tries the target as a component first, then as a module. For components, runs
the full orbit loop until the success condition is met or the ceiling is hit.
For modules, executes all stages sequentially.

## orbit launch

Executes a mission with full lifecycle management.

```bash
# Run a mission
orbit launch <mission-name>

# Preview execution plan
orbit launch <mission-name> --dry-run

# Resume from last waypoint
orbit launch <mission-name> --resume
```

Stages are topologically sorted based on `depends_on` declarations. Circular
dependencies are detected and rejected. Manual gate stages pause for human
approval. The `--resume` flag finds the last completed waypoint and restarts
from the next stage.

## orbit watch

Starts reactive sensor monitoring.

```bash
orbit watch
```

Activates all configured sensors across active components:
- File watch sensors (inotifywait or polling fallback)
- Interval schedule sensors
- Cron schedule sensors

Runs until interrupted (Ctrl+C). Cleans up all sensors and cron entries on exit.

## orbit trigger

Manually fires a trigger for a component.

```bash
orbit trigger <component-name>
```

Creates a trigger file at `.orbit/triggers/{name}-manual` that the watch loop
picks up and dispatches.

## orbit status

Shows system or mission status.

```bash
# Overall system status
orbit status

# Mission-specific status
orbit status <mission-name>
```

Overall status shows: last run ID, active sensor count, pending gates, pending
tool requests. Mission status shows each stage with its completion state.

## orbit registry

Displays the component and mission registry.

```bash
orbit registry
```

Builds the registry from `components/*.yaml` and `missions/*.yaml`, then
displays each entry with its status and description.

## orbit log

Reads event logs.

```bash
# Show all logs
orbit log

# Show last N entries
orbit log --tail 20
```

Parses JSONL entries from `.orbit/logs/*.jsonl` and formats them as
`[timestamp] [level] message`.

## orbit pending

Lists manual approval gates awaiting response.

```bash
orbit pending
```

Shows each pending gate with its ID, mission, options, timeout, and creation
time.

## orbit approve

Approves a manual gate.

```bash
# Approve with default option
orbit approve <gate-id>

# Approve with specific option
orbit approve <gate-id> --option <choice>
```

## orbit reject

Rejects a manual gate.

```bash
orbit reject <gate-id>
```

## orbit decisions

Manages the decision learning store.

```bash
# List decisions for a scope
orbit decisions <target>

# Accept a decision
orbit decisions accept <id-prefix>

# Reject a decision
orbit decisions reject <id-prefix>

# Supersede a decision
orbit decisions supersede <id-prefix> <new-title> <new-content>
```

Targets use scope format: `project`, `mission:<name>`, `component:<name>`.

## orbit insights

Reads insight entries.

```bash
# Read insights for a scope
orbit insights <scope>

# Clear insights for a scope
orbit insights clear <scope>
```

## orbit feedback

Reads feedback entries.

```bash
# Read feedback for a component
orbit feedback <component>

# Clear feedback for a component
orbit feedback clear <component>
```

## orbit tools

Manages tool access governance.

```bash
# List pending tool requests
orbit tools pending

# Grant a tool request
orbit tools grant <tool> <component>

# Deny a tool request
orbit tools deny <tool> <component>

# Show tool request history
orbit tools log
```

## orbit cron

Manages cron-based sensors.

```bash
# List registered cron entries
orbit cron list

# Remove all Orbit cron entries
orbit cron clear

# Preview planned cron entries from registry
orbit cron preview
```

[← Back to Index](index.md)
