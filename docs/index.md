---
title: Orbit Rover Documentation
last_updated: 2026-03-11
---

# Orbit Rover Documentation

Orbit Rover is a bash-based agent orchestration engine — the open-source,
zero-infrastructure tier of the Orbit platform. It runs on any POSIX system
with bash 4+, no compiled runtime required.

Rover implements the **Ralph loop** pattern: a deterministic orbit loop that
invokes an AI agent repeatedly until a success condition is met, with deadlock
detection, checkpoint continuity, and a learning system that accumulates
knowledge across orbits.

## Start Here

| Document | Description |
|----------|-------------|
| [Getting Started](getting-started.md) | Installation, prerequisites, and your first Orbit project |
| [Architecture](architecture.md) | Core design principles, data flow, and system invariants |
| [Studios](studios.md) | Example studio projects to learn from — research, sentinel, fieldops |

## Core Concepts

| Document | Description |
|----------|-------------|
| [Orbit Loop](orbit-loop.md) | The core engine — orbit execution, checkpoints, deadlock detection, and promise flag |
| [Configuration](configuration.md) | `orbit.yaml`, component, mission, and module YAML reference |
| [Adapters](adapters.md) | Agent adapters for claude-code and opencode |
| [Sensors](sensors.md) | File watch, interval schedule, cron delegation, and cascade control |

## Advanced Features

| Document | Description |
|----------|-------------|
| [Learning System](learning-system.md) | Feedback, insights, decisions, and XML tag parsing |
| [Tool System](tool-system.md) | Tool auth keys, policy flags, request governance, and access control |
| [Mission Safety](mission-safety.md) | Flight rules, manual approval gates, waypoints, and retry logic |

## Monitoring

| Document | Description |
|----------|-------------|
| [Dashboard](dashboard.md) | TUI and web dashboard — topology visualization, run history, costs |

## Deployment

| Document | Description |
|----------|-------------|
| [Docker](docker.md) | Running Orbit Rover in a Docker container with auth setup |

## Reference

| Document | Description |
|----------|-------------|
| [CLI Reference](cli-reference.md) | Complete reference for all `orbit` subcommands |
| [State Directory](state-directory.md) | `.orbit/` directory layout, file formats, and JSONL schemas |
| [Compatibility](compatibility.md) | Rover-Station compatibility contract and schema versioning |
