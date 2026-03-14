---
title: Architecture
last_updated: 2026-03-13
---

[← Back to Index](index.md)

# Architecture

## Design Principles

### Bash is the Runtime

Rover is a bash program. No Python runtime, no Node, no compiled binary. The
orbit loop is a `while` loop in bash. Dependencies are limited to bash 4+, jq,
yq (or python3 fallback), and cron for schedule sensors.

### Stateless Agents

Each agent invocation is a fresh subprocess. There are no persistent agent
processes, no session IDs, no conversation continuity between orbits. The agent
is stateless and ephemeral — it starts fresh every orbit.

### Disk is the Only Memory

State lives in `.orbit/`. Insights and decisions live in `.orbit/learning/`.
Feedback is co-located with components. Task state lives in `.orbit/plans/`.
Nothing of value lives in memory between invocations.
Checkpoints bridge orbits by persisting agent context to disk.

### Promise Flag Exit

The orbit loop runs until the success condition is satisfied. `orbits.max` is a
safety ceiling, not the intended exit mechanism. The agent's job is to produce
the deliverable that satisfies the exit condition.

### No Inflight Compaction

Rover has no context window monitoring, no compaction signals, no background
context size checks. Context exhaustion is prevented by task sizing at design
time (the decomposer pattern), not detected at runtime.

## The Ralph Loop

The Ralph loop is the core execution pattern:

```mermaid
flowchart TD
    START([orbit_run_component]) --> STOP{Stop signal?}
    STOP -- Yes --> STOPPED([Exit — stopped])
    STOP -- No --> LOAD[Load checkpoint from disk]
    LOAD --> RENDER[Render prompt template]
    RENDER --> PREFLIGHT[Run preflight hooks]
    PREFLIGHT --> INVOKE[Invoke adapter — fresh subprocess]
    INVOKE --> EXTRACT[Extract checkpoint from output]
    EXTRACT --> PARSE[Parse learning tags]
    PARSE --> HASH[Hash delivers — deadlock detection]
    HASH --> CHECK{Success condition met?}
    CHECK -- Yes --> EXIT([Exit loop ✓])
    CHECK -- No --> DEADLOCK{Stall count ≥ threshold?}
    DEADLOCK -- No --> CEILING{Orbit ceiling hit?}
    DEADLOCK -- Yes --> PERSPECTIVE[Inject perspective prompt]
    PERSPECTIVE --> CEILING
    CEILING -- No --> LOAD
    CEILING -- Yes --> ABORT([Exit — ceiling reached])
```

## Data Flow

```mermaid
flowchart LR
    subgraph Config
        OY[orbit.yaml] --> CLS[config_load_system]
        CY[components/*/*.yaml] --> RB[registry_build]
        MY[missions/*.yaml] --> RB
    end

    CLS --> SYS[ORBIT_SYSTEM]
    RB --> REG[.orbit/registry.json]

    subgraph Trigger
        SENSOR[Sensor fire]
        MANUAL[Manual trigger]
        LAUNCH[orbit launch]
    end

    SENSOR --> ORC
    MANUAL --> ORC
    LAUNCH --> ORC

    subgraph Orbit["orbit_run_component()"]
        ORC[render_template] --> ADAPT[_invoke_adapter]
        ADAPT --> LEARN[parse_learning_tags]
        LEARN --> CKPT[extract_checkpoint]
        CKPT --> HASH[hash_delivers]
        HASH --> SUCC[_check_success]
    end

    ADAPT --> |agent subprocess| AGENT((AI Agent))
    LEARN --> |JSONL| STORE[.orbit/learning/]
    CKPT --> |markdown| STATE[.orbit/state/]
```

## Two-Tier Mission Pattern

Complex work uses a planning tier followed by an implementation tier:

```mermaid
flowchart TD
    M([Mission start]) --> S1

    subgraph S1[Stage 1: decompose]
        DEC[Decomposer component]
        DEC --> TASKS[tasks.json created]
    end

    S1 --> S2

    subgraph S2[Stage 2: execute — loops via orbits_to]
        PICK[Pick first undone task] --> WORK[Do work in one orbit]
        WORK --> MARK[Mark task done]
        MARK --> EXIT_CHECK{All tasks done?}
        EXIT_CHECK -- No --> PICK
        EXIT_CHECK -- Yes --> DONE
    end

    DONE([Mission complete ✓])
```

The decomposer breaks work into atomic tasks stored in `.orbit/plans/`. The
worker processes one task per orbit, checking off completions. The `orbits_to`
mechanism loops the worker stage back to itself until all tasks are done.

## Component Lifecycle

```mermaid
flowchart TD
    ACTIVE([Component: active]) --> TRIGGER

    TRIGGER{How triggered?}
    TRIGGER --> |sensor fire| SENSOR[File / interval / cron]
    TRIGGER --> |manual| RUN[orbit run]
    TRIGGER --> |mission| LAUNCH[orbit launch]

    SENSOR --> ORC
    RUN --> ORC
    LAUNCH --> ORC

    ORC[orbit_run_component]
    ORC --> PRE[Preflight hooks]
    PRE --> LOOP

    subgraph LOOP[Orbit loop — 1..max]
        TMPL[Render template] --> AGENT[Invoke adapter]
        AGENT --> CKPT[Extract checkpoint]
        CKPT --> LEARN[Parse learning tags]
        LEARN --> DL[Deadlock check]
        DL --> SC{Success?}
        SC -- No --> TMPL
    end

    SC -- Yes --> POST[Postflight hooks]
    POST --> DONE([Complete ✓])
```

## Dashboard Architecture

Rover provides two dashboard modes:

**TUI Dashboard** (`orbit dashboard`) — A terminal dashboard using gum for
styled output. Reads `.orbit/` state directly and renders missions, components,
sensors, and gates with progress bars and status icons.

**Web Dashboard** (`orbit dashboard --web`) — A Cytoscape.js topology
visualization served by a Python stdlib HTTP server. The bash entry point
pre-converts YAML configs to JSON using `yq`, then launches a Python server
that reads those JSON files plus `.orbit/` runtime state. No external Python
packages are required.

```mermaid
flowchart LR
    YAML[missions/*.yaml<br>components/*/*.yaml] -->|yq -o=json| CACHE[.orbit/webdash-cache/*.json]
    CACHE --> PY[Python HTTP server<br>stdlib only]
    STATE[.orbit/ runtime state] --> PY
    PY -->|/api/graph| BROWSER[Browser: Cytoscape.js]
    PY -->|/api/events SSE| BROWSER
    PY -->|/static/*| BROWSER
```

The web dashboard shares the same API contract as Orbit Station (Go), meaning
the same frontend code (HTML/CSS/JS) runs against both backends.

See [Dashboard](dashboard.md) for full details.

## Atomic Writes

All writes to JSONL files and state files are atomic. The pattern is:

1. Write content to a `.tmp` file in the same directory
2. `mv` the temp file to the target path
3. The rename is atomic on POSIX filesystems

This prevents partial writes from corrupting state, which is critical since
Rover may be interrupted at any point.

## ID Generation

IDs are generated without requiring `uuidgen`:

```bash
echo -n "${timestamp}${content}${RANDOM}" | sha256sum | head -c 12
```

Prefixed by type: `fb-` (feedback), `ins-` (insight), `dec-` (decision),
`req-` (tool request), `run-` (run).

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success — promise flag satisfied |
| 1 | Failure — ceiling reached, deadlock abort, or stage failure |
| 2 | Flight rule abort |
| 3 | Graceful stop — operator requested via `orbit stop` |

[← Back to Index](index.md)
