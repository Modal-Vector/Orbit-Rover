---
title: Studios
last_updated: 2026-03-11
---

[← Back to Index](index.md)

# Studios

Studios are complete example projects that demonstrate Orbit Rover patterns.
Each studio is a self-contained project with its own `orbit.yaml`, components,
missions, prompts, and scripts.

**Location:** `studios/`

## orbit-research

**Pattern:** Three-mission workflow (plan → research → write)

A research intelligence studio that plans a research agenda, investigates topics,
and writes findings into a polished structured document. Merges the research and
document transformation patterns into a single end-to-end workflow.

### How It Works

```mermaid
flowchart LR
    subgraph Plan["Mission: plan"]
        RP[research-planner]
        RP --> TJ[tasks.json]
    end

    subgraph Research["Mission: research ↻"]
        TD[topic-decomposer] --> R[researcher]
        R -->|orbits_to| TD
    end

    subgraph Write["Mission: write ↻"]
        SD[section-decomposer] --> SW[section-writer]
        SW -->|orbits_to| SD
    end

    Plan --> Research --> Write
```

1. **Plan mission:** `research-planner` reads the research brief and creates a
   topic-level task list in `.orbit/plans/research/tasks.json`
2. **Research mission:** `topic-decomposer` breaks each topic into atomic tasks,
   `researcher` investigates one per orbit with preflight source distillation
3. **Write mission:** `section-decomposer` reads completed findings and creates
   section tasks in `.orbit/plans/research/write-tasks.json`, `section-writer`
   writes one section per orbit

### Components

| Component | Purpose |
|-----------|---------|
| `research-planner` | Creates topic-level research plan |
| `topic-decomposer` | Breaks topics into atomic research tasks |
| `researcher` | Investigates one atomic task per orbit |
| `section-decomposer` | Breaks findings into section writing tasks |
| `section-writer` | Writes one section per orbit |

### Missions

| Mission | Pattern |
|---------|---------|
| `plan` | Sequential (plan) |
| `research` | Iterative (decompose → investigate, weekly cron) |
| `write` | Iterative (decompose → write, loops via `orbits_to`) |

### Extras

- `orbit.yaml.local` — override file for local model/adapter settings
- `scripts/distil-sources.sh` — preflight source distillation
- `scripts/extract-findings.sh` — findings extraction helper
- `fixtures/` — example research brief, task lists, and findings

---

## orbit-sentinel

**Pattern:** Reactive (sensor-driven monitoring)

An intelligence monitoring studio that watches external sources for changes and
produces analysis.

### How It Works

```mermaid
flowchart TD
    CRON["⏰ Cron: daily 06:00"] --> DECOMPOSE

    subgraph Monitor["Mission: monitor"]
        DECOMPOSE[source-decomposer] --> ANALYSE[analyst]
        ANALYSE -->|orbits_to| DECOMPOSE
        ANALYSE --> GATE{brief-gate}
        GATE -->|approve| DONE([Archive & reset])
        GATE -->|reject| ANALYSE
    end
```

1. **Cron sensor** triggers the monitor mission daily at 06:00
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
- `fixtures/` — example watchlist, task list, findings, and daily brief

---

## orbit-fieldops

**Pattern:** Governed tools (autonomous operations with safety controls)

An autonomous operations studio for infrastructure incident response with
governed tool access.

### How It Works

```mermaid
flowchart TD
    TRIGGER["📁 File sensor: logs/anomaly-trigger"] --> DIAG

    subgraph Respond["Mission: respond"]
        DIAG[diagnostician] --> REM[remediator]
        REM -->|orbits_to| DIAG
    end

    subgraph Tools["Tool policy: restricted"]
        REM -.-> |available| NH[notify-operator]
        REM -.-> |available| CH[check-health]
        REM -.-> |requires auth| RS[restart-service]
        REM -.-> |requires auth| ACP[apply-config-patch]
    end

    subgraph Safety["Flight rules"]
        COST["cost-ceiling: $2.00 → abort"]
    end
```

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
- `fixtures/` — example anomaly report, task list, and log file

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
| Research + writing | orbit-research |
| Monitoring / reactive | orbit-sentinel |
| Operations with tools | orbit-fieldops |

[← Back to Index](index.md)
