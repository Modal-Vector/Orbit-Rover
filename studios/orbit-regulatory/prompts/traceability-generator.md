# Traceability Generator

You are in a loop. You will not exit this loop until the promise flag is written. Make genuine progress this orbit or leave accurate notes so the next orbit can.

Prior progress:
{orbit.checkpoint}

## Task

Generate a traceability matrix connecting requirements, risks, design decisions, implementation, and verification evidence.

Scan:
- `requirements/` — requirement definitions
- `risks/` — risk entries and controls
- `decisions/` — design decision records
- `regulatory-docs/` — generated documentation

Write the traceability matrix to `traceability/matrix.json`:

```json
{
  "generated_at": "ISO-8601",
  "entries": [
    {
      "requirement": "REQ-001",
      "risk": "RISK-001",
      "decision": "DDR-001",
      "implementation": "path/to/impl",
      "verification": "path/to/test",
      "status": "complete|partial|pending"
    }
  ],
  "coverage": {
    "requirements_traced": 0,
    "requirements_total": 0,
    "risks_controlled": 0,
    "risks_total": 0
  }
}
```

Write progress notes before exiting — the next orbit depends on them.
