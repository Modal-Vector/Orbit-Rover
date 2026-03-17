# Orbit Rover

Bash-based agent orchestration engine — the open-source, zero-infrastructure
tier of the [Orbit](https://github.com/Modal-Vector/orbit) platform.

Rover runs on any POSIX system with bash 4+ and implements the **Ralph loop**
pattern: a deterministic orbit loop that invokes an AI agent repeatedly until a
success condition is met, with deadlock detection, checkpoint continuity, and a
learning system that accumulates knowledge across orbits.

![TUI Dashboard](docs/images/tui-dashboard.png)

## Quick Start

```bash
# Check dependencies
./orbit doctor

# Create a new project
./orbit init my-project
cd my-project

# Define a component, then run it
./orbit run my-worker

# Launch a multi-stage mission
./orbit launch my-mission

# Monitor with the TUI dashboard
./orbit dashboard

# Or the web dashboard
./orbit dashboard --web
```

> **Note:** `orbit` is a local script, not an installed binary. Run it with
> `./orbit` from the repository root. To use `orbit` from anywhere (including
> the example studios), add the repo root to your PATH:
>
> ```bash
> export PATH="/path/to/Orbit-Rover:$PATH"
> ```
>
> Or add that line to your `~/.zshrc` / `~/.bashrc` for persistence.

## Features

- **Orbit loop** — deterministic agent invocations with checkpoints, deadlock
  detection, and promise-flag exit
- **Missions** — multi-stage pipelines with dependency ordering, waypoints,
  retry logic, and flight rules
- **Sensors** — file watch (inotifywait or polling), interval schedules, cron
  delegation, and cascade control
- **Learning system** — structured feedback, insights, and decisions persisted
  as JSONL, accumulated across orbits
- **Tool governance** — auth keys, policy flags, request/grant/deny workflow
- **Manual gates** — human approval checkpoints with configurable timeouts
- **Modules** — reusable stage groups with parameterised templates
- **Adapters** — pluggable agent backends (Claude Code, OpenCode)
- **Dashboard** — terminal TUI (gum) and web topology graph (Cytoscape.js)

![Web Dashboard](docs/images/web-dashboard.png)

## Requirements

| Dependency | Version | Purpose |
|------------|---------|---------|
| bash | 4.0+ | Runtime |
| jq | any | JSON processing |
| yq | any | YAML parsing (recommended) |
| python3 | 3.7+ | YAML fallback parser; web dashboard server |

At least one agent adapter: `claude` (Claude Code CLI) or `opencode`.

Optional: `inotifywait` (efficient file watching), `cron` (schedule sensors),
`gum` (styled TUI dashboard), `ollama` (local models).

```bash
./orbit doctor   # verify all dependencies
```

## Project Structure

```
my-project/
  orbit.yaml            # system configuration
  components/           # component YAML definitions
  missions/             # mission YAML definitions
  modules/              # reusable module definitions
  prompts/              # prompt templates (Markdown)
  scripts/              # lifecycle hooks
  tools/                # tool scripts and index
  .orbit/               # runtime state (gitignored)
```

## CLI Reference

```
orbit init <name>         Create a new project
orbit run <component>     Run a single component
orbit launch <mission>    Execute a mission
orbit trigger <name>      Fire a manual trigger
orbit watch               Start sensor monitoring
orbit dashboard           TUI dashboard (--web for topology graph)
orbit status              Show system status
orbit registry            Rebuild component/mission registry
orbit log                 View event logs
orbit doctor              Check dependencies
orbit decisions           Manage decisions
orbit insights            Manage insights
orbit feedback            Manage feedback
orbit tools               Tool request governance
orbit pending             List pending approval gates
orbit approve <gate-id>   Approve a gate
orbit reject <gate-id>    Reject a gate
orbit cron                Manage cron sensors
```

See [docs/cli-reference.md](docs/cli-reference.md) for the complete reference.

## Architecture

Rover's core invariants:

- **Bash is the runtime.** The orbit loop is a `while` loop in bash. No
  compiled binary, no Python runtime for the core engine.
- **Stateless agents.** Each invocation is a fresh subprocess. No persistent
  processes, no session continuity between orbits.
- **Disk is the only memory.** All state lives in `.orbit/`. Nothing of value
  lives in memory between invocations.
- **Promise flag exit.** The loop runs until the success condition is satisfied.
  `orbits.max` is a safety ceiling, not the intended exit mechanism.

The `.orbit/` directory format is interchangeable with
[Orbit Station](https://github.com/Modal-Vector/orbit) (Go) — you can start
with Rover and promote to Station without data migration.

See [docs/architecture.md](docs/architecture.md) for the full design.

## Example Studios

Three example projects in `studios/`:

- **orbit-research** — research + writing pipeline (plan, research, write)
- **orbit-sentinel** — intelligence monitoring with file sensors
- **orbit-fieldops** — autonomous field operations with approval gates

## Documentation

| Document | Description |
|----------|-------------|
| [Getting Started](docs/getting-started.md) | Installation and first project |
| [Architecture](docs/architecture.md) | Design principles and data flow |
| [Configuration](docs/configuration.md) | Full YAML reference |
| [Orbit Loop](docs/orbit-loop.md) | Core engine details |
| [Adapters](docs/adapters.md) | Agent adapter configuration |
| [Sensors](docs/sensors.md) | File watch, schedule, cron, cascade |
| [Learning System](docs/learning-system.md) | Feedback, insights, decisions |
| [Tool System](docs/tool-system.md) | Auth keys, policy, governance |
| [Mission Safety](docs/mission-safety.md) | Flight rules, gates, waypoints |
| [Dashboard](docs/dashboard.md) | TUI and web dashboard |
| [CLI Reference](docs/cli-reference.md) | All commands |
| [State Directory](docs/state-directory.md) | `.orbit/` layout and schemas |
| [Studios](docs/studios.md) | Example projects |
| [Config Specs](docs/specs/) | Quick-reference YAML schemas for AI-assisted authoring |

## Contributing

Development instructions for Orbit Rover are in
[CONTRIBUTING.md](CONTRIBUTING.md). To activate development mode for Claude Code
sessions, swap the CLAUDE.md files as described in that file.

## Testing

```bash
# Run all 331 tests
bats tests/

# Run a specific phase
bats tests/phase1-core.bats
```

## License

[Apache License 2.0](LICENSE) -- Modal Vector
