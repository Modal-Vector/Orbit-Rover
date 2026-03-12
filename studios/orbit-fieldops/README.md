# orbit-fieldops — Autonomous Operations Studio

Monitors system logs, diagnoses anomalies, and applies governed remediations
using Orbit Rover's ralph loop pattern.

## Usage

```bash
# Initialise Orbit in this directory
orbit init

# Set up log monitoring (reactive mode)
orbit watch
# Triggers when logs/anomaly-trigger is created by your log processor

# Or launch manually after anomaly detection
orbit launch respond

# Monitor remediation progress
orbit status respond

# Review and grant tool access requests
orbit tools pending
orbit tools grant <request-id>
```

## Edge Deployment

For edge/IoT environments with local models:

```bash
cp orbit.yaml.edge orbit.yaml
# Requires: opencode + ollama with qwen2.5-coder model
```

## How It Works

### Mission: respond

| Stage | Component | Behaviour |
|-------|-----------|-----------|
| `diagnose` (waypoint) | diagnostician | Preflight: `extract-anomalies.sh` parses log files and writes `logs/anomaly-report.json`. Diagnostician analyses patterns, correlates root causes, creates remediation tasks. |
| `remediate` | remediator | Applies one fix per orbit using assigned tools. Postflight: `validate-fix.sh` checks health and verifies no tasks have `verification_failed`. Loops back to diagnose (max 20 orbits). |

**Trigger**: The mission starts when an external log processor creates
`logs/anomaly-trigger`. The sensor uses cascade blocking — a new trigger won't
start a second mission while one is running.

**Exit condition**: All tasks in the remediation plan marked `done: true`.

**Flight rules**: Mission aborts if cumulative cost exceeds $2.00 USD.

## Key Files

| Path | Description |
|------|-------------|
| `logs/anomaly-trigger` | Marker file — external log processor creates this to trigger the mission |
| `logs/anomaly-report.json` | Structured anomaly patterns (preflight output from `extract-anomalies.sh`) |
| `.orbit/plans/fieldops/tasks.json` | Remediation task list (created by diagnostician, consumed by remediator) |
| `.orbit/tool-auth/remediator.json` | Auth keys granted for restricted tools |
| `.orbit/state/remediator/last-health-check.json` | Most recent health check result (written by `check-health` tool) |
| `RISK-REGISTRY.md` | Risk classification and approval policy for all tools |

## Tool Governance

| Tool | Classification | Auth Required | Description |
|------|----------------|---------------|-------------|
| read-logs | available | no | Read specified log files |
| check-health | available | no | Check service health endpoints |
| notify-operator | available | no | Send operator notifications |
| restart-service | restricted | yes | Restart a system service |
| apply-config-patch | restricted | yes | Apply configuration changes |

Restricted tools require a valid `ORBIT_TOOL_AUTH_KEY`. The `_auth-check.sh`
script validates the key against `.orbit/tool-auth/{component}.json` before
allowing execution.

See `RISK-REGISTRY.md` for full risk classification and `tools/INDEX.md` for
tool documentation and instructions on adding new tools.

## Configuration

| File | Purpose |
|------|---------|
| `orbit.yaml` | Model (sonnet), timeout (300s), orbit limits |
| `orbit.yaml.edge` | Edge variant (ollama/qwen2.5-coder, 600s timeout) |
| `missions/respond.yaml` | Mission definition — sensor, flight rules, stage flow |
| `RISK-REGISTRY.md` | Tool risk classifications and approval policy |

## Requirements

- bash 4+, jq, curl
- An AI adapter: `claude-code` (default) or `opencode`
