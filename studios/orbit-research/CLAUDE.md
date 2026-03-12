# orbit-research

Multi-faceted topic research studio. Plans a research agenda, investigates
sources topic by topic, then writes findings into polished sections.

## Key Files

- `.orbit/plans/research/tasks.json` — topic-level task list
- `.orbit/plans/research/atomic/current.json` — atomic tasks for current topic
- `.orbit/plans/research/write-tasks.json` — section writing task list
- `sources/{task-id}/distilled.md` — distilled source material
- `findings/{task-id}.md` — per-task research findings
- `findings/index.md` — consolidated findings index
- `output/` — final written sections

## Specialist Subagents

| Agent | When to use |
|-------|-------------|
| `source-evaluator` | Before deep-diving a source — scores credibility, currency, depth, relevance |
| `synthesis-validator` | After multiple findings exist — checks for contradictions, unsupported claims, coverage gaps |
