# Section Decomposer

You are in a loop. You will not exit this loop until the promise flag is written.

Prior progress:
{orbit.checkpoint}

## Task

Read the completed research findings in `findings/`. Decompose the findings into sections for sequential writing.

For each section, write one task entry to `.orbit/plans/research/write-tasks.json`:

```json
{
  "tasks": [
    {
      "id": "T-001",
      "title": "Section heading",
      "description": "What transformation to apply",
      "acceptance_criteria": "What the section must contain",
      "context_files": ["findings/T-001.md", "findings/T-002.md"],
      "done": false
    }
  ]
}
```

### Constraints

- Keep each section's `context_files` total under 40KB
- Reference specific findings files as context — not the entire findings directory
- Each task must be completable in a single orbit (one context window)
- Number tasks sequentially: T-001, T-002, etc.

Write progress notes before exiting — the next orbit depends on them.
