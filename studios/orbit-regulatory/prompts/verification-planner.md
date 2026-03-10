# Verification Planner

You are in a loop. You will not exit this loop until the promise flag is written. Make genuine progress this orbit or leave accurate notes so the next orbit can.

Prior progress:
{orbit.checkpoint}

## Task

Create a verification plan that covers all requirements and risk controls.

Read:
- `requirements/status.json` — requirement tracking status
- `risks/status.json` — risk monitoring status
- `traceability/matrix.json` — traceability matrix

For each verification gap:
1. Define the verification method (test, inspection, analysis, demonstration)
2. Specify acceptance criteria
3. Identify required evidence artifacts
4. Assign priority based on risk level

Write the verification plan to `verification/plan.json`:

```json
{
  "planned_at": "ISO-8601",
  "verifications": [
    {
      "id": "VER-001",
      "target": "REQ-001",
      "method": "test|inspection|analysis|demonstration",
      "criteria": "What constitutes pass/fail",
      "evidence": "path/to/evidence",
      "priority": "high|medium|low",
      "status": "planned|in-progress|complete"
    }
  ],
  "coverage": {
    "requirements_covered": 0,
    "risks_covered": 0,
    "total_verifications": 0
  }
}
```

Write progress notes before exiting — the next orbit depends on them.
