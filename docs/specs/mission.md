# Mission Configuration Spec

A mission is a multi-stage pipeline that executes components in sequence with
dependency ordering, waypoints, manual gates, outer loops (`orbits_to`), and
flight rules. Missions are launched with `orbit launch`.

## Complete Schema

```yaml
# missions/{name}.yaml

mission: implement                   # required — unique name, must match filename
status: active                       # optional — active | offline (default: active)
description: "Human-readable desc"   # optional — shown in registry and dashboard

# Sensors — triggers for watch mode (orbit watch)
sensors:                             # optional — same schema as component sensors
  paths:
    - "tasks/*/done.flag"
  events: [create, modify]
  debounce: 10s
  schedule:
    cron: "0 2 * * *"               # 5-field cron expression

# Stages — ordered list of execution steps
stages:
  # Component stage — runs a component's orbit loop
  - name: decompose                  # required — unique within mission
    component: task-decomposer       # required — references components/{name}.yaml
    waypoint: true                   # optional — checkpoint for resume on restart (default: false)

  # Component stage with outer loop
  - name: work
    component: worker
    depends_on: [decompose]          # optional — list of stage names that must complete first

    # Outer loop — after this stage completes, loop back to the named stage
    orbits_to: decompose             # optional — stage name to loop back to
    max_orbits: 100                  # required when orbits_to is set — total orbit ceiling across all loops

    # Exit condition for the outer loop (checked after each completion)
    orbit_exit:                      # required when orbits_to is set
      when: bash                     # file | bash
      condition: |                   # file path or bash expression
        jq -e '[.tasks[] | select(.done == false)] | length == 0' \
          {mission.run_dir}/plans/project/tasks.json

  # Manual gate — human approval checkpoint
  - name: review-gate
    type: manual                     # required for gates — must be "manual"
    prompt: |                        # required — shown to the human reviewer
      Review the outputs before proceeding.
      Approve to continue, reject to abort.
    options: [approve, reject]       # required — list of allowed responses
    timeout: 72h                     # optional — auto-resolve after duration (from gate open, not mission start)
    default: reject                  # optional — action taken when timeout expires
    depends_on: [work]               # optional — dependency ordering

  # Module stage — runs a reusable module (see module.md)
  - module: risk-review              # references modules/{name}.yaml
    params:                          # parameter values for the module
      risk_id: RISK-008

# Flight rules — runtime safety constraints
flight_rules:                        # optional
  - name: cost-ceiling               # required — unique within mission
    condition: "metrics.cost_usd < 10.00"  # required — expression evaluated each orbit
    on_violation: abort              # required — abort | warn
    message: "Mission exceeded cost ceiling"  # required — logged/displayed on violation
```

## Minimal Example

```yaml
mission: simple
stages:
  - name: do-work
    component: worker
```

## Real-World Example

From `studios/orbit-fieldops/missions/respond.yaml`:

```yaml
mission: respond
status: active

sensors:
  paths:
    - "logs/anomaly-trigger"
  events: [create]
  cascade: block

stages:
  - name: diagnose
    component: diagnostician
    waypoint: true

  - name: remediate
    component: remediator
    depends_on: [diagnose]
    orbits_to: diagnose
    max_orbits: 20

    orbit_exit:
      when: bash
      condition: |
        jq -e '[.tasks[] | select(.done == false)] | length == 0' \
          {mission.run_dir}/plans/fieldops/tasks.json

flight_rules:
  - name: cost-ceiling
    condition: "metrics.cost_usd < 2.00"
    on_violation: abort
    message: "Fieldops cost ceiling — human review required"
```

## Field Reference

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `mission` | string | — | **Required.** Unique name matching filename |
| `status` | string | `active` | `active` or `offline` |
| `description` | string | — | Human-readable |
| `sensors.paths` | string[] | `[]` | File glob patterns to watch |
| `sensors.events` | string[] | `[]` | Event types (`modify`, `create`, `delete`) |
| `sensors.debounce` | string | system default | Quiet period before triggering |
| `sensors.cascade` | string | `allow` | `allow` or `block` — cascade control mode |
| `sensors.schedule.every` | string | — | Interval duration (e.g. `30m`) |
| `sensors.schedule.cron` | string | — | 5-field cron expression |
| `stages` | list | — | **Required.** Ordered list of stages |
| `stages[].name` | string | — | **Required.** Unique within mission |
| `stages[].component` | string | — | Component name (component stage) |
| `stages[].module` | string | — | Module name (module stage) |
| `stages[].params` | object | — | Parameters for module stage |
| `stages[].type` | string | — | `manual` for gate stages |
| `stages[].depends_on` | list | — | Stage names that must complete first |
| `stages[].waypoint` | boolean | `false` | Checkpoint for mission resume |
| `stages[].orbits_to` | string | — | Stage to loop back to |
| `stages[].max_orbits` | integer | — | **Required with orbits_to.** Total orbit ceiling |
| `stages[].orbit_exit.when` | string | — | `file` or `bash` |
| `stages[].orbit_exit.condition` | string | — | Exit condition for outer loop |
| `stages[].prompt` | string | — | Gate prompt text (manual stages) |
| `stages[].options` | list | — | Gate response options (manual stages) |
| `stages[].timeout` | string | — | Gate timeout duration (e.g. `72h`) |
| `stages[].default` | string | — | Action on gate timeout |
| `flight_rules` | list | — | Runtime safety constraints |
| `flight_rules[].name` | string | — | **Required.** Unique within mission |
| `flight_rules[].condition` | string | — | **Required.** Expression to evaluate |
| `flight_rules[].on_violation` | string | — | **Required.** `abort` or `warn` |
| `flight_rules[].message` | string | — | **Required.** Violation message |

## Common Mistakes

**Using `gate:` wrapper instead of `type: manual`**
```yaml
# WRONG
stages:
  - name: review
    gate:
      prompt: "Approve?"
      options: [approve, reject]

# CORRECT
stages:
  - name: review
    type: manual
    prompt: "Approve?"
    options: [approve, reject]
```

**Missing `orbit_exit` when using `orbits_to`** — Without an exit condition,
the outer loop has no way to stop (except hitting `max_orbits`).
```yaml
# WRONG — loop never exits cleanly
- name: work
  component: worker
  orbits_to: decompose
  max_orbits: 100

# CORRECT
- name: work
  component: worker
  orbits_to: decompose
  max_orbits: 100
  orbit_exit:
    when: bash
    condition: "jq -e '.done' status.json"
```

**`max_orbits` without `orbits_to`** — `max_orbits` is only meaningful on
stages with an outer loop. For single-run stages, the component's own
`orbits.max` controls the iteration limit.

**`timeout` on gates is from gate open, not mission start** — A `timeout: 72h`
means 72 hours from when the gate is opened, not from when the mission began.

**Putting `flight_rules` inside `stages`** — Flight rules are a top-level
mission field, not a property of individual stages.

**Sensors on both mission and component** — If a component defines its own
sensors AND is referenced in a mission that also has sensors, `orbit watch`
can invoke the component both standalone and as part of the mission pipeline,
creating concurrent runs. Define sensors at one level only — typically the
mission. Remove sensors from component YAML if the component is used in any
mission.
