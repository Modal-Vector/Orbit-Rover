# orbit-fieldops

Autonomous operations studio. Diagnoses system anomalies and applies
remediations within a governed tool policy.

## Tool Policy

The remediator operates under a **restricted** tool policy:
- `notify-operator` — always available, use before any restricted action
- `check-health` — always available, use to verify fixes
- `restart-service` — **restricted**, requires auth approval
- `apply-config-patch` — **restricted**, requires auth approval

## Key Files

- `logs/anomaly-report.json` — extracted anomaly patterns
- `.orbit/plans/fieldops/tasks.json` — remediation task list
- `.orbit/tool-auth/remediator.json` — granted auth keys for restricted tools

## Specialist Subagents

| Agent | When to use |
|-------|-------------|
| `log-analyst` | Deep log parsing — root cause isolation, cascade reconstruction, pattern classification |
| `remediation-sequencer` | After creating remediation tasks — validates fix ordering for cascade safety |
| `fix-auditor` | After applying a fix — verifies the anomaly is resolved, not just that health checks pass |
