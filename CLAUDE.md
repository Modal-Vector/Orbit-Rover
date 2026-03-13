# Contributing to Orbit Rover

This file contains development instructions for Claude Code when working on the
Orbit Rover codebase itself (modifying lib/, cmd/, tests/, etc.).

## Activating Development Mode

By default, the root `CLAUDE.md` is configured for **runtime** — helping Claude
perform well when invoked by orbit as an agent. To switch to **development** mode:

```bash
# Activate development CLAUDE.md
mv CLAUDE.md CLAUDE.md.orbit
mv CONTRIBUTING.md CLAUDE.md

# When done developing, restore runtime mode
mv CLAUDE.md CONTRIBUTING.md
mv CLAUDE.md.orbit CLAUDE.md
```

When `CONTRIBUTING.md` is renamed to `CLAUDE.md`, Claude Code will load these
development instructions (coding standards, test requirements, architecture
invariants) instead of the runtime orbit-loop instructions.

---

## Project Overview

Orbit Rover is a bash-based agent orchestration engine — the open-source,
zero-infrastructure tier of the Orbit platform. It runs on any POSIX system
with bash 4+, no compiled runtime required.

**Implementation status:** Complete. All 8 phases implemented, 331 tests passing.

## Reference Documents

| Document | Purpose |
|----------|---------|
| `SPEC.md` | Complete implementation specification — source of truth for all behaviour |
| `PROMPTS.md` | Phase-by-phase build prompts with deliverables, constraints, and verification checklists |
| `docs/` | User-facing documentation (architecture, CLI reference, configuration, etc.) |
| `.orbit/progress.md` | Append-only build log from the initial 8-phase implementation |

Consult `SPEC.md` when modifying behaviour to ensure changes remain spec-compliant.

## Session Continuity

Append a progress note to `.orbit/progress.md` at the end of sessions that
make material changes:

```
## [date] — [area] — [status: complete/partial]
**Completed:** [what was finished and is working]
**Tests:** [bats test status — pass count / total]
**Partial:** [anything started but not finished]
**Blocked:** [anything that needs resolution]
**Next session:** [exactly what to do first]
```

## Architecture Invariants

These are non-negotiable. Never design around them.

**Rover is a bash program.** No Python runtime, no Node, no compiled binary.
The orbit loop is a `while` loop in bash. Dependencies: bash 4+, jq, yq, python3
(YAML parsing only), cron (schedule sensors).

**Each agent invocation is a fresh subprocess.** There are no persistent agent
processes. No session IDs. No conversation continuity between orbits. The agent
is stateless and ephemeral. Start fresh every orbit.

**Disk is the only memory.** State lives in `.orbit/`. Learning lives in
`.orbit/learning/`. Task state lives in `.orbit/plans/`. Nothing of value
lives in memory between invocations.

**The promise flag is the only legitimate exit.** The orbit loop runs until the
success condition is satisfied. `orbits.max` is a safety ceiling, not the
intended exit mechanism.

**No inflight compaction.** Rover has no context window monitoring, no compaction
signals, no background context size checks. Context exhaustion is prevented by
task sizing at design time (the decomposer), not detected at runtime.

## Go Schema Reference

The Station (Go) implementation at `github.com/Modal-Vector/orbit` defines the
canonical YAML schema. Reference these packages for **field names and record
schemas only** — not as implementation patterns:

- `internal/config/` — ComponentConfig, MissionConfig, SensorsConfig, Orbits,
  Retry, ToolsConfig struct field names
- `internal/learning/store.go` — ScopeKind constants (project/mission/module/component/run/stage)
- `internal/insight/`, `internal/decision/`, `internal/feedback/` — JSONL entry schemas
- `internal/manual/` — gate prompt/response file format

Do NOT port Go patterns to bash. Implement every feature using bash-native idioms.
The goal is file-format compatibility so a `.orbit/` directory is interchangeable
between Rover and Station.

## Repository Layout

```
orbit/                        ← repository root
├── CLAUDE.md                 ← runtime instructions (orbit-invoked sessions)
├── CONTRIBUTING.md           ← this file (development instructions)
├── SPEC.md                   ← implementation specification
├── PROMPTS.md                ← build prompts (historical reference)
├── orbit                     ← main CLI entry point (bash executable)
├── lib/
│   ├── util.sh               ← shared helpers: logging, ID gen, atomic writes
│   ├── orbit_loop.sh         ← core orbit loop
│   ├── template.sh           ← prompt template rendering ({key} substitution)
│   ├── hash.sh               ← delivers hashing for deadlock detection
│   ├── extract.sh            ← XML tag extraction from agent output
│   ├── config.sh             ← YAML config loading (system, component, mission, module)
│   ├── registry.sh           ← component/mission registry (.orbit/registry.json)
│   ├── yaml.sh               ← low-level yq helpers (python3 fallback)
│   ├── watch.sh              ← watch mode main loop
│   ├── manual_gate.sh        ← manual approval gates (prompt/response/timeout)
│   ├── flight_rules.sh       ← flight rule evaluation (warn/abort)
│   ├── waypoints.sh          ← waypoint checkpoint/resume
│   ├── retry.sh              ← retry logic (constant/exponential backoff)
│   ├── adapters/
│   │   ├── claude_code.sh    ← claude-code adapter
│   │   └── opencode.sh       ← opencode adapter
│   ├── sensors/
│   │   ├── file_watch.sh     ← inotifywait / polling sensor
│   │   ├── schedule.sh       ← interval + cron sensors
│   │   └── cascade.sh        ← cascade control
│   ├── learning/
│   │   ├── feedback.sh       ← feedback JSONL (votes, assembly)
│   │   ├── insights.sh       ← insights JSONL (scope routing, assembly)
│   │   ├── decisions.sh      ← decisions JSONL (lifecycle: propose/accept/reject/supersede)
│   │   └── parse_tags.sh     ← XML tag → learning store routing
│   ├── tools/
│   │   ├── auth.sh           ← auth key generation + validation
│   │   ├── policy.sh         ← adapter flag building
│   │   └── requests.sh       ← tool request governance
│   └── webdash/              ← web dashboard (Python stdlib server)
│       ├── server.py         ← HTTP server + routing
│       ├── graph_builder.py  ← graph topology builder (port of Go graph.go)
│       ├── api_handlers.py   ← API endpoint handlers
│       ├── learning_handlers.py ← learning JSONL readers
│       └── static/           ← frontend (HTML/CSS/JS from Station)
│           ├── index.html
│           ├── css/dashboard.css
│           ├── js/*.js       ← 8 app modules (api, graph, layout, panels, etc.)
│           └── js/vendor/    ← vendored Cytoscape.js, dagre, plugins
├── cmd/
│   ├── init.sh               ← orbit init
│   ├── doctor.sh             ← orbit doctor
│   ├── launch.sh             ← orbit launch (mission execution)
│   ├── run.sh                ← orbit run (component/module execution)
│   ├── trigger.sh            ← orbit trigger
│   ├── status.sh             ← orbit status
│   ├── registry_cmd.sh       ← orbit registry
│   ├── log.sh                ← orbit log
│   ├── dashboard.sh          ← orbit dashboard (TUI via gum + web via python3)
│   ├── learning.sh           ← orbit decisions/insights/feedback
│   ├── tools_cli.sh          ← orbit tools (pending/grant/deny/log)
│   ├── cron_cli.sh           ← orbit cron (list/clear/preview)
│   ├── gates.sh              ← orbit pending/approve/reject
│   └── watch_cmd.sh          ← orbit watch
├── scripts/
│   └── _auth-check.sh        ← standalone auth gate (no lib sourcing)
├── docs/                     ← user-facing documentation
├── studios/
│   ├── orbit-research/       ← research + writing studio (plan → research → write)
│   ├── orbit-sentinel/       ← intelligence monitoring studio
│   └── orbit-fieldops/       ← autonomous operations studio
└── tests/
    ├── helpers/              ← bats-support, bats-assert
    ├── fixtures/             ← YAML configs, mock adapters, sample outputs
    ├── phase1-core.bats      ← 46 tests
    ├── phase2-config.bats    ← 57 tests
    ├── phase3-sensors.bats   ← 37 tests
    ├── phase4-learning.bats  ← 43 tests
    ├── phase5-tools.bats     ← 33 tests
    ├── phase6-cli.bats       ← 38 tests
    ├── phase7-safety.bats    ← 38 tests
    └── phase8-studios.bats   ← 39 tests (331 total)
```

## Implementation Status

All 8 phases are complete (331/331 tests passing as of 2026-03-11):

| Phase | Area | Key modules |
|-------|------|-------------|
| 1 | Core engine | `orbit_loop.sh`, adapters, `template.sh`, `hash.sh`, `extract.sh` |
| 2 | YAML parsing | `config.sh`, `registry.sh`, `yaml.sh` |
| 3 | Sensors | `file_watch.sh`, `schedule.sh`, `cascade.sh`, `watch.sh` |
| 4 | Learning | `feedback.sh`, `insights.sh`, `decisions.sh`, `parse_tags.sh` |
| 5 | Tool system | `auth.sh`, `policy.sh`, `requests.sh` |
| 6 | CLI | `orbit` entry point, all subcommands in `cmd/` |
| 7 | Mission safety | `manual_gate.sh`, `flight_rules.sh`, `waypoints.sh`, `retry.sh` |
| 8 | Example studios | research, sentinel, fieldops |

## Testing

```bash
# Run all tests (331 total)
bats tests/

# Run tests for a specific phase
bats tests/phase1-core.bats

# Run a single test
bats tests/phase1-core.bats --filter "deadlock detection"
```

All changes must pass `bats tests/` with zero failures before being considered
complete. Add tests for any new functionality or bug fixes.

Test files: `tests/phase{1-8}-*.bats`
Fixtures: `tests/fixtures/` — YAML configs, mock adapters, sample outputs.

## Coding Standards

**Error handling:** Every function that can fail must handle failure explicitly.
Use `set -euo pipefail` at the top of each lib file. Functions that are expected
to sometimes return non-zero (e.g. `cascade_is_active`) must be called with `||`
or inside `if`.

**Atomic writes:** All writes to JSONL files and state files must be atomic.
Write to a `.tmp` file, then `mv` to the target. Never append partial JSON.

**Unsupported fields:** The warning list in `config.sh` must exactly match
SPEC.md §20. When Rover encounters a Station-tier field, it warns and continues.
It never errors on unrecognised fields.

**ID generation:** Do not require `uuidgen`. Generate IDs as:
```bash
echo -n "${timestamp}${content}${RANDOM}" | sha256sum | head -c 12
```
Prefix with type: `fb-`, `ins-`, `dec-`, `req-`.

**YAML parsing:** Use `yq` for all YAML access. If yq unavailable, fall back to
`python3 -c "import yaml, sys; ..."`. Never use sed/awk on YAML structure.

**Portability:** Target bash 4+ on Linux and macOS. Use `$(command -v tool)` not
`which tool`. Use `mktemp` not fixed temp paths. Sub-second sleep (`sleep 0.5`)
must fall back to `sleep 1` if not supported.

## Unsupported Station Fields (warn and ignore)

```
resource_pool
inflight
streams, streams.backend
webhooks
serve, serve.enabled, serve.port
deployment: contained
deployment: c2
state.backend: postgres  (warn, fall back to file)
```

Warning format:
```
[ROVER WARN] orbit.yaml: 'webhooks' not supported in Rover (Station feature). Use file sensors as an alternative.
```

## Key Behaviours (Easy to Break)

When modifying these areas, read the relevant SPEC.md section first.

**Deadlock detection** hashes the content of files listed in `delivers[]`.
An empty or absent delivers list means deadlock detection is disabled for that
component. Hash must use file *content*, not metadata (mtime, size).

**Checkpoint extraction:** if agent output contains `<checkpoint>...</checkpoint>`,
use that content verbatim. Otherwise take the last 500 words of the raw output.
Cap at 500 words either way. Write to `.orbit/state/{component}/checkpoint.md`.
Overwrite each orbit (only keep the latest checkpoint).

**Cron registration** adds a tagged comment on the same line as the entry:
```
0 9 * * 1 /path/to/project/orbit trigger my-mission  # orbit-rover:my-mission
```
The `# orbit-rover:{name}` tag is the only mechanism for cleanup. Never remove
crontab entries without this tag.

**Cascade block:** when `cascade: block` is set and the component's own delivers
files change while it is executing (i.e. it's the component that changed them),
the file sensor must not re-trigger the component. Check `.orbit/cascade/active.json`
before firing any file sensor trigger.

**Learning scope resolution:** `<insight target="component:doc-drafter">` routes
to `.orbit/learning/insights/component.doc-drafter.jsonl`. The component name is
the part after `component:`. Validate against the registry and warn if not found.

**orbits_to outer loop:** when a mission stage has `orbits_to: {stage_name}`,
after each worker completion the engine checks `orbit_exit.condition`. If false,
it loops back to the named stage and runs it again. `max_orbits` is a ceiling
across the entire outer loop, not per inner cycle.

**Manual gate timeout:** `timeout: 72h` means 72 hours from gate open time, not
from mission start. Store `timeout_at` as ISO-8601 in `prompt.json`. The polling
loop compares `date -u +%s` to the parsed `timeout_at` epoch on every iteration.
