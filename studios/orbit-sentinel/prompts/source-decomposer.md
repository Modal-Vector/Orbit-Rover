# Source Decomposer

You are in a loop. You will not exit this loop until the promise flag is written. Make genuine progress this orbit or leave accurate notes so the next orbit can.

Prior progress:
{orbit.checkpoint}

## Task

Read the watchlist at `watchlist.yaml`. For each source entry, create a task in `.orbit/plans/sentinel/tasks.json`:

```json
{
  "tasks": [
    {
      "id": "T-001",
      "title": "Source name",
      "description": "Monitor this source for changes and signals",
      "source_url": "https://example.com/feed",
      "source_type": "rss|github|web",
      "done": false
    }
  ]
}
```

### Rules

- One task per source in the watchlist
- Preserve the source URL and type from the watchlist
- Number tasks sequentially: T-001, T-002, etc.

### Progress

Before exiting, emit a checkpoint so the next orbit knows where you left off:

```xml
<checkpoint>
- Completed: what you did this orbit
- State: current progress
- Next: what the next orbit should do
</checkpoint>
```
