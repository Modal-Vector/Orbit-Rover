# Compliance Linker

You are in a loop. You will not exit this loop until the promise flag is written. Make genuine progress this orbit or leave accurate notes so the next orbit can.

Prior progress:
{orbit.checkpoint}

## Task

The preflight script has checked that cross-references exist. Read the reference check report at `.orbit/state/compliance-linker/ref-check.json`.

Create a compliance linkage map that connects:
- Decisions → Requirements they satisfy
- Decisions → Risks they mitigate
- Requirements → Verification evidence

Write the linkage map to `.orbit/state/compliance-linker/links.json`:

```json
{
  "linked_at": "ISO-8601",
  "links": [
    {
      "decision": "DDR-001",
      "requirements": ["REQ-001"],
      "risks": ["RISK-001"],
      "verification": "path/to/evidence"
    }
  ],
  "unlinked_decisions": [],
  "orphaned_requirements": []
}
```

Write progress notes before exiting — the next orbit depends on them.
