# orbit-research — Research Intelligence Studio

Researches multi-faceted topics, synthesises findings, and writes them into
structured documents using Orbit Rover's three-mission ralph loop pattern.

## Usage

```bash
# Initialise Orbit in this directory
orbit init

# Write your research brief to a file (e.g., brief.md)

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

### Planning Tier
The `research-planner` reads your brief and creates a topic-level task list.

### Research Tier
1. **Decompose**: `topic-decomposer` picks the next topic and creates atomic tasks
2. **Investigate**: `researcher` processes one atomic task per orbit:
   - Preflight fetches and distils sources (HTML/PDF → 8KB text)
   - Researcher analyses distilled content, writes findings
   - Loops until all atomic tasks are done, then moves to next topic

### Writing Tier
1. **Decompose**: `section-decomposer` reads completed findings and creates section tasks
2. **Write**: `section-writer` processes one section per orbit:
   - Reads findings and task requirements
   - Writes polished output to `output/`
   - Loops until all sections are complete

## Configuration

- `orbit.yaml`: Model, timeout, orbit limits
- `orbit.yaml.local`: Local model variant (ollama/llama3.2)
- `missions/research.yaml`: Cron schedule, max orbits

## Requirements

- bash 4+, jq, curl, python3
- An AI adapter: `claude-code` (default) or `opencode`
- For PDF sources: `pdftotext` (optional, from poppler-utils)
