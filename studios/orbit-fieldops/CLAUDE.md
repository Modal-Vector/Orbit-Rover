# orbit-fieldops

Autonomous operations studio. Diagnoses system anomalies and applies
remediations within a governed tool policy.

## Tool Policy

The remediator operates under a **restricted** tool policy:
- `notify-operator` — always available, use before any restricted action
- `check-health` — always available, use to verify fixes
- `restart-service` — **restricted**, requires auth approval
- `apply-config-patch` — **restricted**, requires auth approval

## Specialist Subagents

Use these via the Agent tool when working in this studio.

| Agent | When to spawn | What it returns |
|-------|---------------|-----------------|
| `log-analyst` | Deep-dive on anomaly logs — pass it log files or anomaly report data | Root cause isolation, cascade reconstruction, pattern classification (transient/intermittent/persistent/cascading/periodic) |
| `remediation-sequencer` | After creating remediation tasks — pass it the tasks file | Dependency analysis, cascade risk assessment, and fix ordering recommendations |
| `fix-auditor` | After applying a fix — pass it the anomaly details and health check results | Four-layer verification (surface, anomaly-specific, recurrence, collateral) with a RESOLVED/NOT RESOLVED verdict |
