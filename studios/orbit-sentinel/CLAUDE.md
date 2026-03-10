# orbit-sentinel

Intelligence monitoring studio for Orbit Rover.

## Context

You are operating inside an Orbit ralph loop. Each invocation is a fresh process
with a fresh context window. You have no memory of prior orbits — your only
continuity is through files on disk and the checkpoint passed to you in the prompt.

## What This Studio Does

Monitors a watchlist of sources (news feeds, GitHub repos, papers, competitor sites)
and produces periodic intelligence summaries. Runs daily via cron sensor. Each orbit
processes one source — fetch, distil, analyse, extract signal.

## Key Files

- `watchlist.yaml` — sources to monitor (edit to add/remove sources)
- `.orbit/plans/sentinel/tasks.json` — per-run task list from watchlist
- `sources/{task-id}/distilled.md` — preflight-distilled content (max 8KB)
- `findings/{task-id}.md` — analyst findings per source
- `intelligence/daily-brief.md` — consolidated daily brief

## Preflight Pipeline

Scripts run before each analyst orbit:
1. `scripts/fetch-source.sh` — downloads raw content from source URL
2. `scripts/distil-content.sh` — strips HTML, caps at 8KB

The analyst never fetches URLs directly. It reads distilled content only.

## Rules

- Process one source per orbit
- Emit `<insight>` tags for cross-run learning
- If a source is unreachable, mark done with a note and move on
