# orbit-research

Research intelligence studio for Orbit Rover. Researches a multi-faceted topic,
synthesises findings, and transforms them into a polished structured document.

## Missions

1. `orbit launch plan` — planner reads the research brief, creates topic-level tasks
2. `orbit launch research` — decomposes topics into atomic tasks, investigates one per orbit
3. `orbit launch write` — decomposes findings into sections, writes one per orbit

## Key Files

- `.orbit/plans/research/tasks.json` — topic-level task list from planner
- `.orbit/plans/research/atomic/current.json` — atomic tasks for current topic
- `.orbit/plans/research/write-tasks.json` — section-level task list for writing
- `sources/{task-id}/distilled.md` — preflight-distilled source material
- `findings/{task-id}.md` — per-task research findings
- `findings/index.md` — consolidated findings index
- `output/` — final written sections

## Specialist Subagents

These are available via the Agent tool for delegation within an orbit:

| Agent | When to use |
|-------|-------------|
| `source-evaluator` | Before committing an orbit to a source — scores credibility, currency, depth, relevance |
| `synthesis-validator` | After multiple findings exist — checks for contradictions, unsupported claims, coverage gaps |

## Rules

- Process one atomic task per orbit (research) or one section per orbit (write)
- Always distil sources via preflight — never fetch URLs in the agent
- Update findings index after completing each topic
