# orbit-research — Research Intelligence Studio

Researches multi-faceted topics, synthesises findings, and writes them into
structured documents using Orbit Rover's ralph loop pattern.

## Setup

The `orbit` command is a script in the Orbit Rover repository root — it is not
installed on your PATH by default. Before running the commands below, do one of:

```bash
# Option 1: Add Orbit Rover to your PATH (recommended)
export PATH="/path/to/Orbit-Rover:$PATH"

# Option 2: Use a relative path from this directory
alias orbit='../../orbit'
```

## Usage

```bash
# Initialise Orbit in this directory
orbit init

# Write your research brief to brief.md (see brief.md for the expected format)

# Step 1: Plan the research
orbit launch plan

# Step 2: Execute the research
orbit launch research

# Step 3: Write up the findings
orbit launch write

# Monitor progress
orbit status research
orbit status write

# For weekly automated research runs
orbit watch
# (registers cron: "0 8 * * 1" — every Monday at 08:00)
```

## Privacy-First Mode

To run entirely on local models with no cloud API calls:

```bash
cp orbit.yaml.local orbit.yaml
# Requires: opencode + ollama with llama3.2 model pulled
```

## How It Works

### Missions

| Mission | Trigger | Stages |
|---------|---------|--------|
| `plan` | Manual | research-planner |
| `research` | Cron (Mon 08:00) or manual | topic-decomposer → researcher (max 200 orbits) |
| `write` | Manual | section-decomposer → section-writer (max 50 orbits) |

### Planning (mission: plan)

The `research-planner` reads `brief.md` and creates a topic-level task list.
This is a waypoint — the mission pauses for review before continuing.

### Research (mission: research)

1. **Decompose** (waypoint): `topic-decomposer` picks the next incomplete topic
   and breaks it into atomic research tasks
2. **Investigate**: `researcher` processes one atomic task per orbit:
   - Preflight: `distil-sources.sh` fetches source URLs and strips HTML/PDF to
     8KB plain text; `extract-findings.sh` rebuilds `findings/index.md` from
     all existing findings
   - The researcher analyses distilled content and writes findings
   - Loops back to decompose when the current topic is complete, until all
     topics are done

### Writing (mission: write)

1. **Decompose** (waypoint): `section-decomposer` reads completed findings and
   creates section-level writing tasks with acceptance criteria
2. **Write**: `section-writer` processes one section per orbit:
   - Reads `brief.md` for audience, voice, and output format
   - Reads the findings listed in the task's `context_files`
   - Writes polished prose to `output/`
   - Loops until all sections are complete

## Key Files

| Path | Description |
|------|-------------|
| `brief.md` | Research brief — objective, audience, voice, scope, output format |
| `.orbit/plans/research/tasks.json` | Topic-level task list (created by planner) |
| `.orbit/plans/research/atomic/current.json` | Atomic tasks for the current topic |
| `.orbit/plans/research/write-tasks.json` | Section writing task list |
| `sources/{task-id}/distilled.md` | Distilled source material (max 8KB, preflight output) |
| `findings/{task-id}.md` | Per-task research findings |
| `findings/index.md` | Auto-generated index of all findings (rebuilt each orbit by `extract-findings.sh`) |
| `output/` | Final written sections |

## Configuration

| File | Purpose |
|------|---------|
| `orbit.yaml` | Model (sonnet), timeout (300s), orbit limits |
| `orbit.yaml.local` | Local model variant (ollama/llama3.2, 600s timeout) |
| `missions/plan.yaml` | Plan mission definition |
| `missions/research.yaml` | Research mission — cron schedule, max orbits |
| `missions/write.yaml` | Write mission — max orbits |

## Requirements

- bash 4+, jq, curl, python3
- An AI adapter: `claude-code` (default) or `opencode`
- For PDF sources: `pdftotext` (optional, from poppler-utils)
