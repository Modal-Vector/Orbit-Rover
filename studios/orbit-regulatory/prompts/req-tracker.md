# Requirement Tracker

You are in a loop. You will not exit this loop until the promise flag is written. Make genuine progress this orbit or leave accurate notes so the next orbit can.

Prior progress:
{orbit.checkpoint}

## Task

Track the implementation and verification status of all requirements.

Scan:
- `requirements/` — requirement definitions
- `traceability/matrix.json` — current traceability state

For each requirement, determine:
1. Implementation status (implemented, partial, pending)
2. Verification status (verified, partial, pending)
3. Trace completeness (linked to risk, decision, evidence)

Write the status report to `requirements/status.json`:

```json
{
  "tracked_at": "ISO-8601",
  "requirements": [
    {
      "id": "REQ-001",
      "implementation": "implemented|partial|pending",
      "verification": "verified|partial|pending",
      "trace_complete": true
    }
  ],
  "summary": {
    "total": 0,
    "implemented": 0,
    "verified": 0,
    "fully_traced": 0
  }
}
```

Write progress notes before exiting — the next orbit depends on them.
