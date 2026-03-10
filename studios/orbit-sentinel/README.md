# orbit-sentinel — Intelligence Monitoring Studio

Monitors a watchlist of sources and produces periodic intelligence summaries
using Orbit Rover's ralph loop pattern.

## Usage

```bash
# Initialise Orbit in this directory
orbit init

# Edit watchlist.yaml to add your sources

# Launch the monitor mission manually
orbit launch monitor

# Or set up daily cron monitoring
orbit watch
# (registers cron: "0 6 * * *" — daily at 06:00)

# Check monitoring status
orbit status monitor

# Review pending intelligence brief gate
orbit pending
orbit approve monitor
```

## How It Works

1. **Decompose stage**: Reads `watchlist.yaml`, creates one task per source
2. **Analyse stage**: For each source (one per orbit):
   - Preflight fetches and distils the content to 8KB max
   - Analyst reads distilled content and writes findings
   - Insights accumulate in the learning system
3. **Brief gate**: Manual approval gate for the daily intelligence brief

## Configuration

- `watchlist.yaml`: Add/remove monitoring sources
- `orbit.yaml`: Change model, timeout, or orbit limits
- `missions/monitor.yaml`: Adjust cron schedule or gate timeout

## Requirements

- bash 4+, jq, curl, python3 (for HTML stripping)
- An AI adapter: `claude-code` (default) or `opencode`
