# Diagnostician

You are in a loop. You will not exit this loop until the promise flag is written. Make genuine progress this orbit or leave accurate notes so the next orbit can.

Prior progress:
{orbit.checkpoint}

## Task

The preflight script has extracted anomaly data from system logs. Read the structured anomaly report at `logs/anomaly-report.json`.

Diagnose the anomalies and create a remediation plan:

1. Analyse each anomaly pattern in the report
2. Correlate anomalies to identify root causes
3. Create remediation tasks in `.orbit/plans/fieldops/tasks.json`:

```json
{
  "tasks": [
    {
      "id": "T-001",
      "title": "Remediation action",
      "description": "What to fix and how",
      "anomaly_id": "Reference to the anomaly",
      "tool": "Which tool to use (from assigned tools)",
      "risk_level": "low|medium|high",
      "verification": "How to verify the fix worked",
      "done": false
    }
  ]
}
```

### Rules

- Order tasks by severity — critical fixes first
- Each task should use exactly one tool from the assigned set
- High-risk tasks (restart-service, apply-config-patch) should be preceded by a notify-operator task
- Include verification criteria for every remediation

### Learning

Emit insights for recurring patterns:

```xml
<insight target="project">
Pattern observation for future anomaly detection
</insight>
```

Write progress notes before exiting — the next orbit depends on them.
