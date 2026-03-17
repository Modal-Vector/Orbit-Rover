# Changelog

All notable changes to Orbit Rover will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.0] - 2026-03-17

Initial open-source release.

### Added
- Core orbit loop with deadlock detection, checkpoint continuity, and promise-flag exit
- YAML configuration system for components, missions, modules, and system settings
- Agent adapters for Claude Code and OpenCode
- Prompt template rendering with variable substitution and perspective injection
- Sensors: file watch (inotifywait/polling), interval schedules, cron delegation, cascade control
- Watch mode for continuous sensor monitoring
- Learning system: feedback, insights, and decisions as scoped JSONL stores
- Tool governance: auth keys, policy flags, request/grant/deny workflow
- Mission safety: manual approval gates, flight rules (warn/abort), waypoints, retry logic
- CLI with 17 subcommands (init, run, launch, watch, dashboard, status, log, doctor, etc.)
- TUI dashboard (gum) and web topology graph (Cytoscape.js)
- Component and mission registry with automatic discovery
- Module system for reusable parameterised stage groups
- Three example studios: orbit-research, orbit-sentinel, orbit-fieldops
- 331 bats tests across 8 phases
- Full documentation suite (architecture, configuration, CLI reference, etc.)
