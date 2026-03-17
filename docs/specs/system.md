# System Configuration Spec (orbit.yaml)

The system config is the project-level settings file. It lives at the project
root as `orbit.yaml` and defines defaults inherited by all components.

## Complete Schema

```yaml
# orbit.yaml

system: orbit                        # required — must be "orbit"
version: 1                           # required — schema version

# Defaults — inherited by all components unless overridden
defaults:
  agent: claude-code                 # optional — claude-code | opencode (default: claude-code)
  model: sonnet                      # optional — sonnet | opus | haiku (default: sonnet)
  timeout: 300                       # optional — seconds per orbit invocation (default: 300)
  max_turns: 10                      # optional — agent turn limit per orbit (default: 10)

# System settings
settings:
  log_level: info                    # optional — debug | info | warn | error (default: info)
  workspace: .                       # optional — project root path (default: .)
  state_dir: .orbit                  # optional — state directory path (default: .orbit)

# Orbit loop defaults
orbits:
  default_max: 20                    # optional — default orbits.max per component (default: 20)
  deadlock_threshold: 3              # optional — consecutive identical outputs before deadlock (default: 3)

# Sensor defaults
sensors:
  debounce_default: 5s               # optional — default debounce for file sensors (default: 5s)

# Resource budgets (informational — not enforced by Rover core)
resources:
  budgets:
    tokens: 500000                   # optional — token budget
    cost_usd: 25.00                  # optional — cost ceiling in USD
    warn_at_percent: 80              # optional — warning threshold percentage

# State backend
state:
  backend: file                      # optional — Rover supports "file" only (default: file)
                                     # "postgres" warns and falls back to file

# NOT SUPPORTED IN ROVER (warns and ignores):
# streams:
# streams.backend:
# serve:
# serve.enabled:
# serve.port:
# webhooks:
# resource_pool:
# inflight:
# resources.pools:
# deployment: contained | c2
```

## Minimal Example

```yaml
system: orbit
version: 1
```

All defaults apply — `claude-code` agent, `sonnet` model, 300s timeout, 10 max turns.

## Real-World Example

From `studios/orbit-research/orbit.yaml`:

```yaml
system: orbit
version: 1

defaults:
  agent: claude-code
  model: sonnet
  timeout: 300
  max_turns: 10

settings:
  log_level: info
  workspace: .
  state_dir: .orbit

orbits:
  default_max: 20
  deadlock_threshold: 3
```

## Field Reference

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `system` | string | — | **Required.** Must be `"orbit"` |
| `version` | integer | — | **Required.** Must be `1` |
| `defaults.agent` | string | `claude-code` | `claude-code` or `opencode` |
| `defaults.model` | string | `sonnet` | `sonnet`, `opus`, `haiku` (opencode: pass-through) |
| `defaults.timeout` | integer | `300` | Seconds per orbit invocation |
| `defaults.max_turns` | integer | `10` | Agent turn limit per orbit |
| `settings.log_level` | string | `info` | `debug`, `info`, `warn`, `error` |
| `settings.workspace` | string | `.` | Project root path |
| `settings.state_dir` | string | `.orbit` | State directory path |
| `orbits.default_max` | integer | `20` | Default max orbits per component |
| `orbits.deadlock_threshold` | integer | `3` | Deadlock detection threshold |
| `sensors.debounce_default` | string | `5s` | Default sensor debounce |
| `resources.budgets.tokens` | integer | — | Token budget |
| `resources.budgets.cost_usd` | number | — | Cost ceiling (USD) |
| `resources.budgets.warn_at_percent` | integer | — | Warning threshold % |
| `state.backend` | string | `file` | `file` only in Rover |

## Common Mistakes

**Missing `system:` or `version:`** — Both are required. Without them,
`orbit doctor` and `orbit run` will fail to load the config.

**Using Go-engine-tier fields and expecting them to work** — Fields like
`streams:`, `serve:`, `webhooks:`, and `resource_pool:` are silently warned
and ignored. Rover logs:
```
[ROVER WARN] orbit.yaml: 'webhooks' not supported in Rover (Go engine feature). Use file sensors as an alternative.
```

**`state.backend: postgres`** — Rover warns and falls back to `file`.
Postgres state requires the Go engine.

**`deadlock_threshold` flat under `orbits:`** — The system config uses a flat
`orbits.deadlock_threshold` key (unlike components which nest it under
`orbits.deadlock.threshold`). This is correct for orbit.yaml.
