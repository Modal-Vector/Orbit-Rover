# Source Decomposer

You are in a loop. You will not exit this loop until the promise flag is written. Make genuine progress this orbit or leave accurate notes so the next orbit can.

Prior progress:
{orbit.checkpoint}

What has happened so far:
{orbit.progress}

## Task

Read the watchlist at `watchlist.yaml`. For each source entry, create an analyst task in `{mission.run_dir}/plans/sentinel/tasks.json`. Your job is to turn each watchlist entry into a **specific analytical brief** — not just copy the source metadata.

The `description` field is the analyst's primary instruction. It must tell the analyst exactly what to look for, what signals matter, and what to flag. A vague description like "monitor for changes" is useless — the analyst needs concrete guidance.

```json
{
  "tasks": [
    {
      "id": "T-001",
      "title": "Source name",
      "description": "Specific analytical instructions — see guidance below",
      "source_url": "https://example.com/feed",
      "source_type": "rss|github|web",
      "priority": "high|medium|low",
      "tags": ["tag1", "tag2"],
      "done": false
    }
  ]
}
```

### Writing the description

Use the source's type, tags, and priority to determine what the analyst should focus on. The description must answer: **what specifically should the analyst look for in this source?**

Examples of good descriptions:
- `"Scan CVE feed for critical/high severity advisories. Flag any affecting web frameworks, container runtimes, or supply chain tooling. Note exploit availability and patch status."`
- `"Identify front-page discussions about agent orchestration, AI tooling, or developer workflow automation. Capture community sentiment and any benchmarks or comparisons cited."`
- `"Review new papers for advances in tool-use, planning, or multi-agent coordination. Flag papers with code releases or benchmark results that challenge current approaches."`

Examples of bad descriptions:
- `"Monitor this source for changes and signals"` — too vague, analyst doesn't know what matters
- `"Check for updates"` — not actionable
- `"Watch for relevant content"` — relevant to what?

Base the description on:
- **tags**: these define the domain — security sources need different analysis than research sources
- **priority**: high-priority sources warrant deeper scrutiny and lower signal thresholds
- **source_type**: RSS feeds deliver structured items; web pages need pattern extraction

### Rules

- One task per source in the watchlist
- Preserve the source URL, type, priority, and tags from the watchlist
- Number tasks sequentially: T-001, T-002, etc.
- Every description must be specific enough that a different analyst could execute it without additional context

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
