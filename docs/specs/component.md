# Component Configuration Spec

A component is a single agent loop — one AI agent invoked repeatedly until a
success condition is met. Components are the atomic execution unit in Orbit.
They can run standalone (`orbit run`) or as stages within a mission.

## Complete Schema

```yaml
# components/{name}/{name}.yaml

component: worker                    # required — unique name, must match directory and filename
status: active                       # optional — active | offline (default: active)
description: "Human-readable desc"   # optional — shown in registry and dashboard

# Agent configuration (all override system defaults from orbit.yaml)
agent: claude-code                   # optional — claude-code | opencode (default: from orbit.yaml defaults.agent)
model: sonnet                        # optional — sonnet | opus | haiku (default: from orbit.yaml defaults.model)
prompt: components/worker/worker.md   # required — path to prompt template (relative to project root)
timeout: 300                         # optional — seconds per orbit invocation (default: from orbit.yaml defaults.timeout)
max_turns: 10                        # optional — agent turn limit per orbit (default: from orbit.yaml defaults.max_turns)

# Sensors — triggers for watch mode (orbit watch)
sensors:
  paths:                             # optional — file glob patterns that trigger this component
    - "decisions/**/*.yaml"
    - "requirements/**/*.yaml"
  events: [create, modify]           # optional — create | modify | delete (default: all)
  debounce: 5s                       # optional — cooldown after trigger (default: from orbit.yaml sensors.debounce_default)
  cascade: allow                     # optional — allow | block (default: allow)
                                     #   block = own delivers won't re-trigger this component
  schedule:
    every: 24h                       # optional — interval: Xh | Xm | Xs
    # OR (mutually exclusive with every)
    cron: "0 9 * * 1"               # optional — 5-field cron expression (uses system crontab)

# What this component produces
delivers:                            # optional — file paths used for cascade and deadlock detection
  - "output/report.json"
  - "output/report.md"

# Lifecycle hooks — bash scripts run before/after agent
preflight:                           # optional — run before each orbit (distil inputs, validate preconditions)
  - scripts/distil-requirements.sh
  - scripts/validate-inputs.sh

postflight:                          # optional — run after each orbit
  - scripts/log-result.sh

# Orbit loop configuration
orbits:
  max: 20                            # optional — max orbit iterations (default: from orbit.yaml orbits.default_max)
  success:                           # required for meaningful work
    when: file                       # required — file | bash
    condition: output/done.flag      # required — file path (when: file) or bash expression (when: bash)
  deadlock:                          # optional — deadlock detection config
    threshold: 3                     # optional — consecutive identical deliver hashes = deadlock (default: from orbit.yaml orbits.deadlock_threshold)
    action: perspective              # optional — perspective | abort (default: perspective)
                                     #   perspective = inject reframe prompt, reset counter, try again
                                     #   abort = mark component failed, stop loop

# Retry on timeout or transient failure
retry:                               # optional — all retry fields are optional
  max_attempts: 2                    # default: 1 (no retry)
  backoff: exponential               # exponential | constant (default: constant)
  initial_delay: 5s                  # default: 5s
  max_delay: 60s                     # default: 60s
  on_timeout: true                   # whether to retry on timeout (default: false)

# Tool system
tools:                               # optional — tool governance
  assigned:                          # list of tool names available to this component
    - read-file
    - write-file
    - run-tests
  policy: standard                   # standard | restricted (default: standard)
                                     #   standard = tools passed without restriction
                                     #   restricted = only assigned tools via --allowedTools
```

## Minimal Example

```yaml
component: hello
prompt: components/hello/hello.md

orbits:
  max: 5
  success:
    when: file
    condition: output/hello.md
```

## Real-World Example

From `studios/orbit-fieldops/components/diagnostician/diagnostician.yaml`:

```yaml
component: diagnostician
prompt: components/diagnostician/diagnostician.md

preflight:
  - scripts/extract-anomalies.sh

delivers:
  - .orbit/plans/fieldops/tasks.json

orbits:
  max: 5
  success:
    when: file
    condition: .orbit/plans/fieldops/tasks.json
```

## Field Reference

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `component` | string | — | **Required.** Unique name matching directory and filename |
| `status` | string | `active` | `active` or `offline` |
| `description` | string | — | Human-readable, shown in registry |
| `agent` | string | system default | `claude-code` or `opencode` |
| `model` | string | system default | `sonnet`, `opus`, `haiku` (opencode: pass-through) |
| `prompt` | string | — | **Required.** Path to prompt template |
| `timeout` | integer | system default | Seconds per orbit invocation |
| `max_turns` | integer | system default | Agent turn limit (circuit breaker) |
| `sensors.paths` | list | — | File glob patterns |
| `sensors.events` | list | all | `create`, `modify`, `delete` |
| `sensors.debounce` | string | system default | Cooldown duration |
| `sensors.cascade` | string | `allow` | `allow` or `block` |
| `sensors.schedule.every` | string | — | Interval (`24h`, `30m`, `10s`) |
| `sensors.schedule.cron` | string | — | 5-field cron expression |
| `delivers` | list | — | Output file paths |
| `preflight` | list | — | Pre-orbit bash scripts |
| `postflight` | list | — | Post-orbit bash scripts |
| `orbits.max` | integer | system default | Max orbit iterations |
| `orbits.success.when` | string | — | `file` or `bash` |
| `orbits.success.condition` | string | — | File path or bash expression |
| `orbits.deadlock.threshold` | integer | system default | Consecutive identical hashes |
| `orbits.deadlock.action` | string | `perspective` | `perspective` or `abort` |
| `retry.max_attempts` | integer | `1` | Total attempts (1 = no retry) |
| `retry.backoff` | string | `constant` | `exponential` or `constant` |
| `retry.initial_delay` | string | `5s` | First retry delay |
| `retry.max_delay` | string | `60s` | Maximum retry delay |
| `retry.on_timeout` | boolean | `false` | Retry on agent timeout |
| `tools.assigned` | list | — | Tool names for this component |
| `tools.policy` | string | `standard` | `standard` or `restricted` |

## Prompt Template Variables

In addition to `{orbit.n}`, `{orbit.checkpoint}`, `{orbit.max}`, and
`{component.name}`, prompts can use `{orbit.progress}` — the accumulated
operational log from the current run. See `docs/specs/prompt.md` for the full
variable list and `<progress>` tag documentation.

## Common Mistakes

**`success:` at top level instead of under `orbits:`**
```yaml
# WRONG
orbits:
  max: 20
success:
  when: file
  condition: output/done.flag

# CORRECT
orbits:
  max: 20
  success:
    when: file
    condition: output/done.flag
```

**Flat `deadlock_threshold` instead of nested `deadlock.threshold`**
```yaml
# WRONG
orbits:
  max: 20
  deadlock_threshold: 3

# CORRECT
orbits:
  max: 20
  deadlock:
    threshold: 3
```

**`cron:` at sensor level instead of under `schedule:`**
```yaml
# WRONG
sensors:
  cron: "0 9 * * 1"

# CORRECT
sensors:
  schedule:
    cron: "0 9 * * 1"
```

**`perspective:` as a top-level field** — This field is not read by the engine.
Deadlock reframe prompts are generated automatically when `deadlock.action: perspective`.
Remove any `perspective:` field from your component YAML.

**Using `every:` and `cron:` together** — These are mutually exclusive under
`sensors.schedule:`. Use one or the other.
