# orbit-scholar

Research intelligence studio for Orbit Rover.

## Context

You are operating inside an Orbit ralph loop. Each invocation is a fresh process
with a fresh context window. You have no memory of prior orbits — your only
continuity is through files on disk and the checkpoint passed to you in the prompt.

## What This Studio Does

Researches a multi-faceted topic and synthesises findings into a structured report.
Uses a two-tier pattern: a planning mission creates the research agenda, then the
research mission executes it topic by topic.

## Two-Tier Pattern

1. `orbit launch plan` — planner reads the research brief, creates topic-level tasks
2. `orbit launch research` — decomposes topics into atomic tasks, investigates one per orbit

## Key Files

- `.orbit/plans/scholar/tasks.json` — topic-level task list from planner
- `.orbit/plans/scholar/atomic/current.json` — atomic tasks for current topic
- `sources/{task-id}/distilled.md` — preflight-distilled source material
- `findings/{task-id}.md` — per-task research findings
- `findings/index.md` — consolidated findings index

## Preflight Pipeline

Scripts run before each researcher orbit:
1. `scripts/distil-sources.sh` — fetches and distils sources (HTML/PDF → text, 8KB cap)
2. `scripts/extract-findings.sh` — builds findings index from completed topics

## Rules

- Process one atomic task per orbit
- Always distil sources via preflight — never fetch URLs in the agent
- Update findings index after completing each topic
