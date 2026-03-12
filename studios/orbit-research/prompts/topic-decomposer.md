# Topic Decomposer

You are in a loop. You will not exit this loop until the promise flag is written. Make genuine progress this orbit or leave accurate notes so the next orbit can.

Prior progress:
{orbit.checkpoint}

## Task

Read `.orbit/plans/research/tasks.json`. Find the next incomplete topic (first where `done` is `false`).

Break this topic into atomic research tasks and write them to `.orbit/plans/research/atomic/current.json`:

```json
{
  "topic_id": "T-001",
  "atomic_tasks": [
    {
      "id": "T-001-A",
      "title": "Specific research step",
      "source_url": "URL to investigate",
      "focus": "What to extract from this source",
      "done": false
    }
  ]
}
```

### Rules

- Each atomic task should be completable in one orbit
- Include specific source URLs where known
- Order by information dependency — gather facts before synthesis
- The final atomic task for each topic should be a synthesis step

### Progress

Before exiting, emit a checkpoint so the next orbit knows where you left off:

```xml
<checkpoint>
- Completed: what you did this orbit
- State: current progress
- Next: what the next orbit should do
</checkpoint>
```

If you notice patterns about task sizing or decomposition, emit an insight:

```xml
<insight target="component:topic-decomposer">Observation about decomposition</insight>
```
