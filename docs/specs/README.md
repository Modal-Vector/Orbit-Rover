# Orbit Configuration Spec Reference

Quick-reference schema documents for authoring Orbit YAML configurations.
These are optimised for use as AI context — paste the relevant doc when
asking any AI tool to help create or debug Orbit configs.

| Document | What it covers |
|----------|----------------|
| [component.md](component.md) | Component YAML — agents, sensors, orbits, tools |
| [mission.md](mission.md) | Mission YAML — stages, gates, flight rules, orbits_to loops |
| [module.md](module.md) | Module YAML — reusable parameterised stage groups |
| [system.md](system.md) | System config (orbit.yaml) — defaults, settings, sensors |
| [prompt.md](prompt.md) | Prompt templates — variables, XML tags, learning system |

## Source of Truth

These docs reflect what [`lib/config.sh`](../../lib/config.sh) actually parses.
When in doubt, the implementation and tests are canonical.
