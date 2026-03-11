---
title: Configuration
last_updated: 2026-03-11
---

[← Back to Index](index.md)

# Configuration

All configuration is in YAML, parsed via `yq` with a `python3` fallback.

## System Configuration — `orbit.yaml`

The root configuration file for an Orbit project.

```yaml
defaults:
  agent: claude-code        # Default adapter (claude-code | opencode)
  model: sonnet             # Default model alias
  timeout: 300              # Default agent timeout in seconds
  max_turns: 10             # Default max agent turns per orbit

settings:
  log_level: info           # Logging verbosity (debug | info | warn | error)
  workspace: "."            # Project root directory
  state_dir: ".orbit"       # State directory path

sensors:
  debounce_default: 5s      # Default sensor debounce period

orbits:
  default_max: 20           # Default orbit ceiling
  deadlock_threshold: 3     # Default consecutive-stall orbits before action
```

All values have defaults — an empty `orbit.yaml` is valid.

## Component Configuration

Component YAML files live in `components/` and define a single agent worker.

```yaml
name: section-writer
description: Writes document sections from task plan
status: active                    # active | paused | disabled
prompt: prompts/section-writer.md # Path to prompt template

# Agent settings (inherit from orbit.yaml defaults if omitted)
agent: claude-code
model: sonnet
timeout: 300
max_turns: 10

# Deliverables — files the component is expected to produce
delivers:
  - output/sections/*.md

# Sensors — reactive triggers
sensors:
  paths:
    - .orbit/plans/tasks.json
  events:
    - modify
  debounce: 5s
  cascade: allow              # allow | block

  schedule:
    every: 30m                # Interval trigger
    cron: "0 9 * * 1"         # Cron expression

# Lifecycle hooks
preflight:
  - scripts/validate-input.sh
postflight:
  - scripts/check-output.sh

# Orbit control
orbits:
  max: 50
  success:
    when: bash                # file | bash
    condition: >
      jq '[.tasks[] | select(.done == false)] | length == 0'
      .orbit/plans/research/tasks.json
  deadlock:
    threshold: 3
    action: perspective       # perspective | abort

# Retry on adapter failure
retry:
  max_attempts: 3
  backoff: exponential        # constant | exponential
  initial_delay: 5s
  max_delay: 60s
  on_timeout: false

# Tool governance
tools:
  policy: standard            # standard | restricted
  assigned:
    - read-logs
    - check-health
```

### Field Reference

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `name` | string | required | Unique component identifier |
| `description` | string | — | Human-readable description |
| `status` | string | `active` | Component status |
| `prompt` | string | required | Path to prompt template |
| `agent` | string | system default | Adapter name |
| `model` | string | system default | Model alias |
| `timeout` | integer | system default | Agent timeout (seconds) |
| `max_turns` | integer | system default | Max agent turns per orbit |
| `delivers` | string[] | `[]` | Files the component produces |
| `sensors.paths` | string[] | `[]` | File glob patterns to watch |
| `sensors.events` | string[] | `[]` | Event types (modify, create, delete) |
| `sensors.debounce` | string | system default | Quiet period before triggering |
| `sensors.cascade` | string | `allow` | Cascade control mode |
| `sensors.schedule.every` | string | — | Interval duration (e.g. `30m`) |
| `sensors.schedule.cron` | string | — | Cron expression |
| `preflight` | string[] | `[]` | Scripts to run before orbit loop |
| `postflight` | string[] | `[]` | Scripts to run after orbit loop |
| `orbits.max` | integer | system default | Orbit ceiling |
| `orbits.success.when` | string | — | Success check mode (`file` or `bash`) |
| `orbits.success.condition` | string | — | File path or bash expression |
| `orbits.deadlock.threshold` | integer | system default | Stall count before action |
| `orbits.deadlock.action` | string | `perspective` | Deadlock response |
| `retry.max_attempts` | integer | `0` | Max retry attempts |
| `retry.backoff` | string | `constant` | Backoff strategy |
| `retry.initial_delay` | string | `5s` | First retry delay |
| `retry.max_delay` | string | `60s` | Maximum retry delay |
| `retry.on_timeout` | boolean | `false` | Retry on timeout (exit 124) |
| `tools.policy` | string | `standard` | Tool access policy |
| `tools.assigned` | string[] | `[]` | Allowed tool names |

## Mission Configuration

Mission YAML files live in `missions/` and orchestrate multiple components.

```yaml
name: transform
description: Transform a source document

stages:
  - name: decompose
    component: section-decomposer

  - name: write
    component: section-writer
    depends_on:
      - decompose
    orbits_to: decompose       # Loop back until exit condition

  - name: review-gate
    gate:
      prompt: "Approve the output?"
      options:
        - approve
        - reject
      timeout: 72h
      default: approve
    depends_on:
      - write

flight_rules:
  - name: cost_limit
    condition: "metrics.cost_usd < 10.0"
    on_violation: abort
    message: "Cost exceeded $10 limit"

  - name: orbit_ceiling
    condition: "metrics.orbit_count < 100"
    on_violation: warn
    message: "Approaching orbit ceiling"
```

### Stage Fields

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Unique stage identifier |
| `component` | string | Component to execute |
| `depends_on` | string[] | Stages that must complete first |
| `orbits_to` | string | Stage to loop back to (outer loop) |
| `gate` | object | Manual approval gate (instead of component) |
| `gate.prompt` | string | Question shown to approver |
| `gate.options` | string[] | Available response options |
| `gate.timeout` | string | Timeout duration (e.g. `72h`) |
| `gate.default` | string | Default option on timeout |

### Flight Rule Fields

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Rule identifier |
| `condition` | string | Expression using `metrics.*` placeholders |
| `on_violation` | string | `abort` or `warn` |
| `message` | string | Message shown on violation |

Available metrics: `metrics.total_tokens`, `metrics.cost_usd`,
`metrics.duration_seconds`, `metrics.orbit_count`.

## Module Configuration

Modules are reusable stage groups with parameters, defined in `modules/`.

```yaml
name: research-block
description: Parameterised research pipeline
parameters:
  - topic
  - depth

stages:
  - name: plan-{topic}
    component: research-planner
  - name: research-{topic}
    component: researcher
    depends_on:
      - plan-{topic}

delivers:
  - output/{topic}-report.md
```

Run with parameters:

```bash
./orbit run research-block --params '{"topic":"ai-safety","depth":"deep"}'
```

## Unsupported Station Fields

Rover warns and ignores these Station-tier fields in YAML:

| Field | Warning | Alternative |
|-------|---------|-------------|
| `resource_pool` | Station feature | — |
| `inflight` | Station feature | — |
| `streams` / `streams.backend` | Station feature | — |
| `webhooks` | Station feature | Use file sensors |
| `serve` / `serve.enabled` / `serve.port` | Station feature | — |
| `deployment: contained` | Station feature | — |
| `deployment: c2` | Station feature | — |
| `state.backend: postgres` | Station feature | Falls back to file |

Warning format:
```
[ROVER WARN] orbit.yaml: 'webhooks' not supported in Rover (Station feature). Use file sensors as an alternative.
```

[← Back to Index](index.md)
