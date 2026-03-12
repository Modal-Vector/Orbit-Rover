# orbit-sentinel

Intelligence monitoring studio for Orbit Rover. Monitors a watchlist of sources
and produces periodic intelligence summaries. Runs daily via cron sensor.

## Key Files

- `watchlist.yaml` — sources to monitor (edit to add/remove sources)
- `.orbit/plans/sentinel/tasks.json` — per-run task list from watchlist
- `sources/{task-id}/distilled.md` — preflight-distilled content (max 8KB)
- `findings/{task-id}.md` — analyst findings per source
- `intelligence/daily-brief.md` — consolidated daily brief

## Specialist Subagents

These are available via the Agent tool for delegation within an orbit:

| Agent | When to use |
|-------|-------------|
| `signal-correlator` | After generating findings — detects patterns across sources and prior runs |
| `threat-enricher` | When encountering CVEs or security advisories — adds CVSS, ATT&CK, exploit context |

## Rules

- Process one source per orbit
- If a source is unreachable, mark done with a note and move on
