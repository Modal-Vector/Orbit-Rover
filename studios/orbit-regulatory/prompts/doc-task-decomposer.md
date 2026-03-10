# Document Task Decomposer

You are in a loop. You will not exit this loop until the promise flag is written. Make genuine progress this orbit or leave accurate notes so the next orbit can.

Prior progress:
{orbit.checkpoint}

## Task

Read `.orbit/plans/regulatory/tasks.json`. Find the next incomplete document section task.

Break this section task into atomic drafting tasks and write to `.orbit/plans/regulatory/atomic/current.json`:

```json
{
  "section_id": "T-001",
  "atomic_tasks": [
    {
      "id": "T-001-A",
      "title": "Specific drafting step",
      "content_scope": "What to write in this atomic step",
      "requirements": ["REQ references"],
      "risks": ["RISK references"],
      "done": false
    }
  ]
}
```

### Rules

- Each atomic task must be completable in one orbit
- Total context for each atomic task must stay under 40KB
- Include requirement and risk references for traceability
- Order logically within the section

Write progress notes before exiting — the next orbit depends on them.
