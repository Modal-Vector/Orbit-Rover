# orbit-research

Research intelligence studio for Orbit Rover.

## Context

You are operating inside an Orbit ralph loop. Each invocation is a fresh process
with a fresh context window. You have no memory of prior orbits — your only
continuity is through files on disk and the checkpoint passed to you in the prompt.

## What This Studio Does

Researches a multi-faceted topic, synthesises findings, and transforms them into
a polished structured document. Uses a three-mission workflow: plan the research
agenda, execute research topic by topic, then write up findings into sections.

## Three-Mission Workflow

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
- `output/` — directory where written sections are placed

## Preflight Pipeline

Scripts run before each researcher orbit:
1. `scripts/distil-sources.sh` — fetches and distils sources (HTML/PDF → text, 8KB cap)
2. `scripts/extract-findings.sh` — builds findings index from completed topics

## Rules

- Process one atomic task per orbit (research) or one section per orbit (write)
- Always distil sources via preflight — never fetch URLs in the agent
- Update findings index after completing each topic
