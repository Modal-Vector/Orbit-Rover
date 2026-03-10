# Risk Monitor

You are in a loop. You will not exit this loop until the promise flag is written. Make genuine progress this orbit or leave accurate notes so the next orbit can.

Prior progress:
{orbit.checkpoint}

## Task

Monitor the status of all identified risks and their control measures.

Scan:
- `risks/` — risk entries
- `traceability/matrix.json` — traceability state

For each risk:
1. Current severity and likelihood assessment
2. Control measure implementation status
3. Residual risk level
4. Verification of control effectiveness

Write the risk status to `risks/status.json`:

```json
{
  "monitored_at": "ISO-8601",
  "risks": [
    {
      "id": "RISK-001",
      "severity": "low|medium|high|critical",
      "controls_implemented": true,
      "residual_risk": "acceptable|tolerable|unacceptable",
      "verification": "verified|pending"
    }
  ],
  "summary": {
    "total": 0,
    "controlled": 0,
    "verified": 0,
    "unacceptable": 0
  }
}
```

Write progress notes before exiting — the next orbit depends on them.
