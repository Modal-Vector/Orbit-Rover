# orbit-fieldops

Autonomous operations studio for Orbit Rover. Monitors system logs for
anomalies, diagnoses issues, and applies remediations within a governed tool
policy. Triggered reactively by anomaly detection.

## Tool Policy

The remediator operates under a **restricted** tool policy:
- `notify-operator` — always available, use before any restricted action
- `check-health` — always available, use to verify fixes
- `restart-service` — **restricted**, requires auth approval
- `apply-config-patch` — **restricted**, requires auth approval

## Key Files

- `logs/anomaly-trigger` — sensor trigger file
- `logs/anomaly-report.json` — preflight-extracted anomaly patterns
- `.orbit/plans/fieldops/tasks.json` — remediation task list
- `.orbit/tool-auth/remediator.json` — granted auth keys for restricted tools

## Specialist Subagents

These are available via the Agent tool for delegation within an orbit:

| Agent | When to use |
|-------|-------------|
| `log-analyst` | Deep log parsing — root cause isolation, cascade reconstruction, pattern classification |
| `remediation-sequencer` | After diagnostician creates tasks — validates fix ordering for cascade safety |
| `fix-auditor` | After applying a fix — verifies the anomaly is resolved, not just that health checks pass |

## Flight Rules

- **cost-ceiling**: Mission aborts if cost exceeds $2.00 USD
- Operator notification required before service restarts

## Rules

- Apply one fix per orbit
- Always validate with check-health after applying a fix
- Notify operator before using restricted tools
