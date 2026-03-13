# Module Configuration Spec

A module is a reusable group of stages with parameterised names. Modules let
you define a pattern once (e.g. "review a risk") and instantiate it multiple
times in missions with different parameters.

## Complete Schema

```yaml
# modules/{name}.yaml

module: risk-review                  # required — unique name, must match filename
status: active                       # optional — active | offline (default: active)
description: "Human-readable desc"   # optional — shown in registry

# Parameters — placeholders expanded with {param_name} syntax
parameters:                          # optional — defines available parameters
  risk_id:
    required: true                   # whether the param must be provided
    description: "Risk identifier"   # human-readable description

# Stages — same schema as mission stages, with {param} placeholders
stages:
  - name: "validate-{risk_id}"      # {risk_id} replaced at instantiation
    component: ddr-validator

  - name: "analyse-{risk_id}"
    component: regulatory-analyst
    depends_on:
      - "validate-{risk_id}"        # placeholders work in depends_on too

# What the module produces (placeholders expanded)
delivers:                            # optional
  - "traceability/risk-{risk_id}-report.md"
```

## Usage in a Mission

Reference a module in a mission's stages list using `module:` instead of `component:`:

```yaml
# missions/compliance.yaml
mission: compliance
stages:
  - module: risk-review
    params:
      risk_id: RISK-008

  - module: risk-review
    params:
      risk_id: RISK-012
```

Each instantiation expands all `{risk_id}` placeholders, creating distinct
stage names (`validate-RISK-008`, `analyse-RISK-008`, etc.).

## Minimal Example

```yaml
module: build-and-test

stages:
  - name: build
    component: builder
  - name: test
    component: tester
    depends_on: [build]
```

## Real-World Example

From `tests/fixtures/module-risk-review.yaml`:

```yaml
module: risk-review
status: active
description: "Verify risk control chain for a specific risk ID"

parameters:
  risk_id:
    required: true
    description: "Risk identifier (e.g. RISK-008)"

stages:
  - name: "validate-{risk_id}"
    component: ddr-validator

  - name: "analyse-{risk_id}"
    component: regulatory-analyst
    depends_on:
      - "validate-{risk_id}"

delivers:
  - "traceability/risk-{risk_id}-report.md"
```

## Field Reference

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `module` | string | — | **Required.** Unique name matching filename |
| `status` | string | `active` | `active` or `offline` |
| `description` | string | — | Human-readable |
| `parameters` | object | — | Parameter definitions |
| `parameters.{name}.required` | boolean | `false` | Whether param must be provided |
| `parameters.{name}.description` | string | — | Human-readable param description |
| `stages` | list | — | **Required.** Same schema as mission stages |
| `delivers` | list | — | Output file paths (supports `{param}` placeholders) |

## Common Mistakes

**Forgetting `params:` when referencing a module in a mission**
```yaml
# WRONG — required parameter not provided
stages:
  - module: risk-review

# CORRECT
stages:
  - module: risk-review
    params:
      risk_id: RISK-008
```

**Using `$param` instead of `{param}` syntax** — Orbit uses `{param_name}`,
not shell-style `$param` or `${param}`.

**Duplicate stage names across module instantiations** — If you instantiate
the same module twice with the same params, stage names will collide. Always
use unique parameter values.
