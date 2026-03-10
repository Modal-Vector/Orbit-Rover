---
title: Studios
last_updated: 2026-03-10
---

[← Back to Index](index.md)

# Studios

Studios are complete example projects that demonstrate Orbit Rover patterns.
Each studio is a self-contained project with its own `orbit.yaml`, components,
missions, prompts, and scripts.

**Location:** `studios/`

## orbit-docsmith

**Pattern:** Two-tier (decompose + execute)

A document transformation studio that converts source documents (research
papers, specs, raw notes) into structured output.

### How It Works

1. **Decompose stage:** The `section-decomposer` reads the source document and
   creates `.orbit/plans/docsmith/tasks.json` with one task per section
2. **Write stage:** The `section-writer` loops through tasks, writing one
   section per orbit and marking tasks done
3. **Exit condition:** All tasks in `tasks.json` have `done: true`

### Components

| Component | Purpose |
|-----------|---------|
| `section-decomposer` | Breaks source into section tasks |
| `section-writer` | Writes one section per orbit |

### Mission

| Mission | Stages |
|---------|--------|
| `transform` | decompose → write (loops via `orbits_to`) |

### Key Design Choices

- Writer completes exactly one task per orbit (atomic progress)
- Checkpoint carries forward which tasks remain
- `orbits_to` loops the write stage back until all done

---

## orbit-scholar

**Pattern:** Two-tier (planning + research)

A research intelligence studio for structured topic investigation.

### How It Works

1. **Plan mission:** `topic-decomposer` breaks research question into
   sub-topics, `research-planner` creates a research plan
2. **Research mission:** `researcher` executes the plan, investigating each
   sub-topic and producing findings

### Components

| Component | Purpose |
|-----------|---------|
| `topic-decomposer` | Breaks research question into sub-topics |
| `research-planner` | Creates structured research plan |
| `researcher` | Executes research per sub-topic |

### Missions

| Mission | Pattern |
|---------|---------|
| `plan` | Sequential (decompose → plan) |
| `research` | Iterative (researcher loops) |

### Extras

- `orbit.yaml.local` — override file for local model/adapter settings
- `scripts/distil-sources.sh` — postflight source distillation
- `scripts/extract-findings.sh` — findings extraction helper

---

## orbit-sentinel

**Pattern:** Reactive (sensor-driven monitoring)

An intelligence monitoring studio that watches external sources for changes and
produces analysis.

### How It Works

1. **File sensor** watches `watchlist.yaml` for changes
2. When triggered, `source-decomposer` breaks the watchlist into individual
   source monitoring tasks
3. `analyst` processes each source and produces intelligence reports

### Components

| Component | Purpose |
|-----------|---------|
| `source-decomposer` | Breaks watchlist into source tasks |
| `analyst` | Analyses individual sources |

### Mission

| Mission | Pattern |
|---------|---------|
| `monitor` | Sequential (decompose → analyse) |

### Key Design Choices

- Reactive: triggered by changes to watchlist, not on a schedule
- Scripts handle content fetching and distillation
- `watchlist.yaml` defines sources to monitor

---

## orbit-fieldops

**Pattern:** Governed tools (autonomous operations with safety controls)

An autonomous operations studio for infrastructure incident response with
governed tool access.

### How It Works

1. **Diagnostician** analyses system health using `read-logs` and
   `check-health` tools
2. **Remediator** applies fixes using `apply-config-patch`,
   `restart-service`, and `notify-operator` tools
3. Tool access is restricted via policy — agents can only use assigned tools

### Components

| Component | Tools | Policy |
|-----------|-------|--------|
| `diagnostician` | read-logs, check-health | restricted |
| `remediator` | apply-config-patch, restart-service, notify-operator | restricted |

### Mission

| Mission | Pattern |
|---------|---------|
| `respond` | Sequential (diagnose → remediate) |

### Key Design Choices

- All tool scripts validate auth keys before execution
- `tools/INDEX.md` documents available tools
- `RISK-REGISTRY.md` tracks operational risks
- `orbit.yaml.edge` — edge deployment override configuration

---

## orbit-regulatory

**Pattern:** Two-tier + reactive (complex regulatory documentation)

A TGA SaMD (Software as a Medical Device) regulatory documentation studio.
The most complex example, demonstrating multi-mission workflows with many
components.

### Components

| Component | Purpose |
|-----------|---------|
| `doc-planner` | Plans documentation structure |
| `doc-task-decomposer` | Breaks docs into atomic writing tasks |
| `doc-drafter` | Writes document sections |
| `regulatory-analyst` | Analyses regulatory requirements |
| `compliance-linker` | Links requirements to evidence |
| `req-tracker` | Tracks requirement coverage |
| `risk-monitor` | Monitors risk controls |
| `traceability-generator` | Builds traceability matrices |
| `verification-planner` | Plans verification activities |
| `ddr-validator` | Validates design decision records |
| `soup-assessor` | Assesses Software of Unknown Provenance |

### Missions

| Mission | Pattern | Description |
|---------|---------|-------------|
| `plan-docs` | Sequential | Plan documentation structure |
| `generate-docs` | Two-tier | Generate regulatory documents |
| `decision-capture` | Iterative | Capture and validate design decisions |
| `pre-release-gate` | Gate + validation | Pre-release compliance check |

### Key Design Choices

- Multiple specialised components for different regulatory concerns
- Scripts for validation: DDR format checking, reference validation,
  traceability excerpts, risk control extraction
- `RISK-REGISTRY.md` tracks regulatory and operational risks
- Manual gates for pre-release approval

---

## Creating Your Own Studio

1. Run `orbit init my-studio` to scaffold the project
2. Define components in `components/*.yaml`
3. Write prompt templates in `prompts/*.md`
4. Define missions in `missions/*.yaml`
5. Add lifecycle scripts in `scripts/`
6. Add tools in `tools/` (if needed)
7. Test with `orbit run <component>` for individual components
8. Launch with `orbit launch <mission>` for full workflows

Study the existing studios for patterns that match your use case:

| If your task is... | Study |
|---------------------|-------|
| Document transformation | orbit-docsmith |
| Research / investigation | orbit-scholar |
| Monitoring / reactive | orbit-sentinel |
| Operations with tools | orbit-fieldops |
| Complex multi-stage | orbit-regulatory |

[← Back to Index](index.md)
