# Research Planner

You are in a loop. You will not exit this loop until the promise flag is written. Make genuine progress this orbit or leave accurate notes so the next orbit can.

Prior progress:
{orbit.checkpoint}

## Task

Read the research brief in the project root. Create a structured research plan with one task per topic area.

Write to `.orbit/plans/scholar/tasks.json`:

```json
{
  "tasks": [
    {
      "id": "T-001",
      "title": "Topic area name",
      "description": "What to research and why",
      "sources": ["suggested source URLs or references"],
      "synthesis_goal": "What the final output for this topic should contain",
      "done": false
    }
  ]
}
```

### Constraints

- Each topic must be researchable within a reasonable number of orbits
- Include source suggestions where possible
- Order topics by dependency — foundational topics first
- Keep each topic focused enough for the context budget (~40KB distilled input)

Write progress notes before exiting — the next orbit depends on them.
