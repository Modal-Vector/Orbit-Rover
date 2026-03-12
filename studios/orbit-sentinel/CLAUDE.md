# orbit-sentinel

Intelligence monitoring studio. Monitors a watchlist of sources and produces
periodic intelligence summaries.

## Key Files

- `watchlist.yaml` — sources to monitor
- `.orbit/plans/sentinel/tasks.json` — per-run task list
- `sources/{task-id}/distilled.md` — distilled source content (max 8KB)
- `findings/{task-id}.md` — analyst findings per source
- `intelligence/daily-brief.md` — consolidated daily brief

## Specialist Subagents

| Agent | When to use |
|-------|-------------|
| `signal-correlator` | After generating findings — detects patterns across sources and prior runs |
| `threat-enricher` | When encountering CVEs or security advisories — adds CVSS, ATT&CK, exploit context |
