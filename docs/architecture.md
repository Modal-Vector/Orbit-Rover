---
title: Architecture
last_updated: 2026-03-10
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

State lives in `.orbit/`. Learning lives in `.orbit/learning/`. Task state
lives in `.orbit/plans/`. Nothing of value lives in memory between invocations.
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

```
┌─────────────────────────────────────────┐
│              orbit_run_component         │
│                                         │
│  1. Load checkpoint from disk           │
│  2. Render prompt template              │
│     - Inject {orbit.n}, {orbit.max}     │
│     - Inject {orbit.checkpoint}         │
│     - Inject perspective (if deadlock)  │
│  3. Invoke adapter (agent subprocess)   │
│  4. Extract checkpoint from output      │
│  5. Parse learning tags                 │
│  6. Hash delivers (deadlock detection)  │
│  7. Check success condition             │
│     ├── Success → exit loop             │
│     └── Not yet → next orbit            │
│  8. Deadlock check                      │
│     ├── Threshold hit → perspective     │
│     └── Or abort                        │
│  9. Retry on adapter failure            │
│                                         │
│  Repeat until success or ceiling hit    │
└─────────────────────────────────────────┘
```

## Data Flow

```
orbit.yaml
    │
    ▼
config_load_system() ──► ORBIT_SYSTEM{}
                              │
components/*.yaml             │
    │                         │
    ▼                         ▼
registry_build() ──► .orbit/registry.json
    │
    ▼
Manual trigger / Sensor fire
    │
    ▼
orbit_run_component()
    ├── render_template()       ─► prompt with variables
    ├── _invoke_adapter()       ─► agent subprocess
    ├── parse_learning_tags()   ─► insights / decisions / feedback
    ├── extract_checkpoint()    ─► .orbit/state/{component}/checkpoint.md
    ├── hash_delivers()         ─► deadlock detection
    └── _check_success()        ─► exit or continue
```

## Two-Tier Mission Pattern

Complex work uses a planning tier followed by an implementation tier:

```
Mission: transform
    │
    ├── Stage 1: decompose (one-shot)
    │   └── Produces tasks.json with subtasks
    │
    └── Stage 2: execute (loops via orbits_to)
        ├── Orbit 1: pick task, do work, mark done
        ├── Orbit 2: pick next task, do work, mark done
        ├── ...
        └── Orbit N: all tasks done → exit condition met
```

The decomposer breaks work into atomic tasks stored in `.orbit/plans/`. The
worker processes one task per orbit, checking off completions. The `orbits_to`
mechanism loops the worker stage back to itself until all tasks are done.

## Component Lifecycle

```
                  ┌──────────┐
                  │  active   │ ◄── default status
                  └────┬─────┘
                       │
              ┌────────┼────────┐
              ▼        ▼        ▼
         ┌────────┐ ┌───────┐ ┌──────┐
         │ sensor │ │ orbit │ │ orbit│
         │ trigger│ │  run  │ │launch│
         └────┬───┘ └───┬───┘ └──┬───┘
              │         │        │
              ▼         ▼        ▼
         orbit_run_component()
              │
              ├── preflight hooks
              ├── orbit loop (1..max)
              │   ├── render template
              │   ├── invoke adapter
              │   ├── extract checkpoint
              │   ├── parse learning tags
              │   ├── deadlock check
              │   └── success check
              └── postflight hooks
```

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

[← Back to Index](index.md)
