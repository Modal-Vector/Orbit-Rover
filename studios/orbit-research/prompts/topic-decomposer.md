# Topic Decomposer

You are in a loop. You will not exit this loop until the promise flag is written. Make genuine progress this orbit or leave accurate notes so the next orbit can.

Prior progress:
{orbit.checkpoint}

What has happened so far:
{orbit.progress}

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
- **Source diversity**: Avoid clustering all atomic tasks on a single source or source type. Aim for at least two distinct source types per topic (e.g., documentation + blog post, paper + implementation). Different perspectives surface findings that a single source misses.

### Task Granularity

A well-sized atomic task:
- Investigates one source or a small set of closely related sources
- Has a clear, specific focus (not "research everything about X")
- Produces findings that can stand alone — another researcher could read them without needing the source
- Takes roughly one orbit of genuine analytical work, not just copying

**Signs a task is too large:** the focus field contains "and" more than once, or the source is an entire documentation site rather than a specific page or section.

**Signs a task is too small:** the expected findings would be a single sentence, or the task is just "confirm that X exists" with no analysis required.

### Progress

Emit a progress note (~200 words) recording what happened this orbit:

```xml
<progress>
- Done: what was completed
- Skipped: what was blocked and why
- Failed: what was tried and didn't work
</progress>
```

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
