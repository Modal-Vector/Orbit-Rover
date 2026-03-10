# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Orbit Rover is a bash-based agent orchestration engine — the open-source,
zero-infrastructure tier of the Orbit platform. It runs on any POSIX system
with bash 4+, no compiled runtime required.

## Reference Documents

| Document | Purpose |
|----------|---------|
| `SPEC.md` | Complete implementation specification — source of truth for all behaviour |
| `PROMPTS.md` | Phase-by-phase build prompts with deliverables, constraints, and verification checklists |

Read the relevant SPEC.md sections at the start of every session. Do not rely on
memory of prior sessions — re-read the spec for the sections you are implementing.

## You Are in a Loop

This project is built across multiple claude-code sessions, each session is one
orbit. You do not remember previous sessions. Your only memory of prior work is:

1. The files on disk — code, tests, and this CLAUDE.md
2. The progress note in `.orbit/progress.md` (append-only, read it first)

**At the end of every session, append a progress note to `.orbit/progress.md`:**

```
## [date] — [phase] — [status: complete/partial]
**Completed:** [what was finished and is working]
**Tests:** [bats test status — pass count / total]
**Partial:** [anything started but not finished]
**Blocked:** [anything that needs resolution]
**Next session:** [exactly what to do first]
```

Keep notes under 400 words. Future you depends on them.

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
orbit/                        ← rover orphan branch root
├── CLAUDE.md                 ← this file
├── SPEC.md                   ← symlink or copy of orbit-rover-spec.md
├── PROMPTS.md                ← symlink or copy of orbit-rover-build-prompts.md
├── orbit                     ← main CLI entry point (bash executable)
├── lib/
│   ├── orbit_loop.sh         ← core orbit loop (Phase 1)
│   ├── template.sh           ← prompt template rendering (Phase 1)
│   ├── hash.sh               ← delivers hashing for deadlock detection (Phase 1)
│   ├── extract.sh            ← XML tag extraction from agent output (Phase 1)
│   ├── config.sh             ← YAML config loading (Phase 2)
│   ├── registry.sh           ← component/mission registry (Phase 2)
│   ├── yaml.sh               ← low-level yq helpers (Phase 2)
│   ├── watch.sh              ← watch mode main loop (Phase 3)
│   ├── manual_gate.sh        ← manual approval gates (Phase 7)
│   ├── flight_rules.sh       ← flight rule evaluation (Phase 7)
│   ├── waypoints.sh          ← waypoint checkpoint/resume (Phase 7)
│   ├── retry.sh              ← retry logic (Phase 7)
│   ├── adapters/
│   │   ├── claude_code.sh    ← claude-code adapter (Phase 1)
│   │   └── opencode.sh       ← opencode adapter (Phase 1)
│   ├── sensors/
│   │   ├── file_watch.sh     ← inotifywait / polling sensor (Phase 3)
│   │   ├── schedule.sh       ← interval + cron sensors (Phase 3)
│   │   └── cascade.sh        ← cascade control (Phase 3)
│   ├── learning/
│   │   ├── feedback.sh       ← feedback JSONL (Phase 4)
│   │   ├── insights.sh       ← insights JSONL + assembly (Phase 4)
│   │   ├── decisions.sh      ← decisions JSONL + lifecycle (Phase 4)
│   │   └── parse_tags.sh     ← XML tag → learning store routing (Phase 4)
│   └── tools/
│       ├── auth.sh           ← auth key generation + validation (Phase 5)
│       ├── policy.sh         ← adapter flag building (Phase 5)
│       └── requests.sh       ← tool request governance (Phase 5)
├── cmd/
│   ├── init.sh               ← orbit init (Phase 6)
│   ├── doctor.sh             ← orbit doctor (Phase 6)
│   ├── launch.sh             ← orbit launch (Phase 6)
│   ├── run.sh                ← orbit run (Phase 6)
│   ├── trigger.sh            ← orbit trigger (Phase 6)
│   ├── status.sh             ← orbit status (Phase 6)
│   ├── registry.sh           ← orbit registry (Phase 6)
│   └── log.sh                ← orbit log (Phase 6)
├── studios/
│   ├── orbit-docsmith/       ← Phase 8
│   ├── orbit-scholar/        ← Phase 8
│   ├── orbit-sentinel/       ← Phase 8
│   ├── orbit-fieldops/       ← Phase 8
│   └── orbit-regulatory/     ← Phase 8
└── tests/
    ├── helpers/
    │   ├── bats-support/
    │   └── bats-assert/
    ├── fixtures/
    └── [phase-N-name].bats
```

## Current Phase

**Phase:** 8
**Status:** complete
**Last session:** 2026-03-10

Phases in order:
1. Core engine — orbit loop, adapters, template, hash, extract
2. YAML parsing — config loading, registry, unsupported field warnings
3. Sensors — file watch, interval schedule, cron delegation, cascade
4. Learning system — feedback, insights, decisions, tag parsing
5. Tool system — auth keys, policy flags, request governance
6. CLI — orbit binary, all subcommands
7. Mission safety — manual gates, flight rules, waypoints, retry
8. Example studios — docsmith, scholar, sentinel, fieldops, regulatory

## Testing Standard

Every deliverable requires tests. No exceptions.

```bash
# Run all tests
bats tests/

# Run tests for a specific phase
bats tests/phase1-core.bats

# Run a single test
bats tests/phase1-core.bats --filter "deadlock detection"
```

A phase is not complete until `bats tests/` passes with zero failures for all
phases completed so far. Do not start a new phase with failing tests from a
prior phase.

Test file convention:
- `tests/phase1-core.bats`
- `tests/phase2-config.bats`
- `tests/phase3-sensors.bats`
- etc.

Fixture files in `tests/fixtures/` — YAML configs, sample outputs, mock adapters.

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

## Key Behaviours to Get Right

These are the details most likely to be implemented incorrectly. Read each one.

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
