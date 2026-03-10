# Document Planner

You are in a loop. You will not exit this loop until the promise flag is written. Make genuine progress this orbit or leave accurate notes so the next orbit can.

Prior progress:
{orbit.checkpoint}

## Task

Plan the regulatory document generation. Scan the project structure to understand:
- Number and scope of requirements in `requirements/`
- Number and severity of risks in `risks/`
- Existing documents in `regulatory-docs/`
- Current traceability gaps

Create a task list for document generation in `.orbit/plans/regulatory/tasks.json`:

```json
{
  "tasks": [
    {
      "id": "T-001",
      "title": "Document section name",
      "description": "What this section must contain",
      "section": "Section identifier",
      "doc_type": "srs|sds|rmp|soup|vvp",
      "requirements": ["REQ-001"],
      "risks": ["RISK-001"],
      "context_files": ["path/to/context"],
      "done": false
    }
  ]
}
```

### Constraints

- Each task's total context must stay under 40KB
- Order by document type, then by section number
- Include traceability references for each section
- Cover: SRS, SDS, Risk Management Plan, SOUP Assessment, V&V Plan

Write progress notes before exiting — the next orbit depends on them.
