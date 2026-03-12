# orbit-sentinel — Intelligence Monitoring Studio

Monitors a watchlist of sources and produces periodic intelligence summaries
using Orbit Rover's ralph loop pattern.

## Usage

```bash
# Initialise Orbit in this directory
orbit init

# Edit watchlist.yaml to add your sources (see Watchlist Format below)

# Launch the monitor mission manually
orbit launch monitor

# Or set up daily cron monitoring
orbit watch
# (registers cron: "0 6 * * *" — daily at 06:00)

# Check monitoring status
orbit status monitor

# Review the daily intelligence brief before it archives
orbit pending
orbit approve monitor    # approve the brief
orbit reject monitor     # reject to iterate further
```

## How It Works

### Mission: monitor

| Stage | Component | Behaviour |
|-------|-----------|-----------|
| `decompose` (waypoint) | source-decomposer | Reads `watchlist.yaml`, creates one task per source with URL, type, priority, and tags. |
| `analyse` | analyst | One source per orbit. Preflight: `fetch-source.sh` downloads the source; `distil-content.sh` strips HTML and caps at 8KB. Analyst writes findings. Loops back to decompose (max 100 orbits). |
| `brief-gate` | manual gate | Pauses for human review of `intelligence/daily-brief.md`. 12h timeout — defaults to approve if no action taken. |

**Trigger**: Cron schedule, daily at 06:00 UTC.

**Exit condition**: All tasks in the task list marked `done: true`, then the
brief gate passes.

## Watchlist Format

Edit `watchlist.yaml` to define your monitoring sources:

```yaml
sources:
  - name: "Source display name"
    url: "https://example.com/feed"
    type: rss          # rss, github, or web
    priority: high     # high, medium, or low
    tags: [security, advisories]
```

| Field | Required | Description |
|-------|----------|-------------|
| `name` | yes | Display name used as the task title |
| `url` | yes | Source URL to fetch |
| `type` | yes | `rss`, `github`, or `web` — determines how the preflight fetches content |
| `priority` | yes | `high`, `medium`, or `low` — carried through to tasks for triage |
| `tags` | yes | Category tags — carried through to tasks for filtering |

## Key Files

| Path | Description |
|------|-------------|
| `watchlist.yaml` | Sources to monitor — name, URL, type, priority, tags |
| `.orbit/plans/sentinel/tasks.json` | Per-run task list (one task per watchlist source) |
| `sources/{task-id}/distilled.md` | Distilled source content, max 8KB (preflight output) |
| `findings/{task-id}.md` | Analyst findings per source |
| `intelligence/daily-brief.md` | Consolidated daily intelligence brief |

## Configuration

| File | Purpose |
|------|---------|
| `watchlist.yaml` | Add, remove, or reprioritise monitoring sources |
| `orbit.yaml` | Model (sonnet), timeout (300s), orbit limits |
| `missions/monitor.yaml` | Cron schedule, gate timeout, max orbits |

## Requirements

- bash 4+, jq, curl, python3 (for HTML stripping)
- An AI adapter: `claude-code` (default) or `opencode`
