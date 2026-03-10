# orbit-fieldops — Autonomous Operations Studio

Monitors system logs, diagnoses anomalies, and applies governed remediations
using Orbit Rover's ralph loop pattern.

## Usage

```bash
# Initialise Orbit in this directory
orbit init

# Set up log monitoring (reactive mode)
orbit watch
# Triggers when logs/anomaly-trigger is created

# Or launch manually after anomaly detection
orbit launch respond

# Monitor remediation progress
orbit status respond

# Review tool access requests
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

1. **Trigger**: External log processor writes `logs/anomaly-trigger`
2. **Diagnose**: Preflight extracts anomaly patterns; diagnostician creates remediation tasks
3. **Remediate**: One fix per orbit, validated by health checks, governed by tool policy

## Tool Governance

| Tool | Classification | Auth Required |
|------|----------------|---------------|
| read-logs | available | no |
| check-health | available | no |
| notify-operator | available | no |
| restart-service | restricted | yes |
| apply-config-patch | restricted | yes |

See `RISK-REGISTRY.md` for full risk classification.

## Flight Rules

- Cost ceiling: $2.00 USD per mission run (abort on violation)
- Operator notification required before restricted tool use

## Requirements

- bash 4+, jq, curl
- An AI adapter: `claude-code` (default) or `opencode`
