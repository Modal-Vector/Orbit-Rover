# Section Decomposer

You are in a loop. You will not exit this loop until the promise flag is written.

Prior progress:
{orbit.checkpoint}

## Task

Read the source document in the project root. Decompose it into sections for sequential rewriting.

For each section, write one task entry to `.orbit/plans/docsmith/tasks.json`:

```json
{
  "tasks": [
    {
      "id": "T-001",
      "title": "Section heading",
      "description": "What transformation to apply",
      "acceptance_criteria": "What the section must contain",
      "context_files": ["path/to/relevant/file"],
      "done": false
    }
  ]
}
```

### Constraints

- Keep each section's `context_files` total under 40KB
- If the source doc is the only input, include only the relevant excerpt — not the full document unless it fits
- Each task must be completable in a single orbit (one context window)
- Number tasks sequentially: T-001, T-002, etc.

Write progress notes before exiting — the next orbit depends on them.
