#!/usr/bin/env bash
set -euo pipefail

# init.sh — orbit init subcommand
# Creates project structure, orbit.yaml template, .orbit/ state dirs.

cmd_init() {
  local project_name="${1:-$(basename "$(pwd)")}"

  if [[ -f "orbit.yaml" ]]; then
    echo "Error: orbit.yaml already exists in this directory." >&2
    return 1
  fi

  echo "Initialising Orbit project: $project_name"

  # Create project directories
  local dirs=(
    components missions modules prompts scripts tools
    decisions requirements risks verification regulatory-docs
  )
  for d in "${dirs[@]}"; do
    mkdir -p "$d"
  done

  # Create .orbit state directories (SPEC §16)
  local state_dirs=(
    state runs plans work
    learning/feedback learning/insights learning/decisions
    manual tool-auth tool-requests
    cascade sensors triggers logs
  )
  for d in "${state_dirs[@]}"; do
    mkdir -p ".orbit/$d"
  done

  # Write orbit.yaml template
  cat > orbit.yaml <<EOF
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

sensors:
  debounce_default: 5s
EOF

  # Write CLAUDE.md template
  cat > CLAUDE.md <<EOF
# Project: ${project_name}

## Orbit Context

This project runs under Orbit Rover — a bash-based agent orchestration engine.

**You are operating inside an orbit loop.** Each invocation of you is one orbit.
You have a fresh context window. You do not remember previous orbits.
Your only memory of prior work is the progress note in {orbit.checkpoint}.

**The loop exits only when you write the promise flag.**
Do not write the promise flag unless all acceptance criteria are satisfied.
EOF

  # Write RISK-REGISTRY.md template
  cat > RISK-REGISTRY.md <<EOF
# Risk Registry

| ID | Description | Severity | Status |
|----|-------------|----------|--------|
EOF

  # Write tools/INDEX.md template
  cat > tools/INDEX.md <<EOF
# Tool Index

List all tools available to components in this project.

| Tool | Description | Policy |
|------|-------------|--------|
EOF

  # Copy _auth-check.sh if it exists in ORBIT_ROOT
  if [[ -n "${ORBIT_ROOT:-}" ]] && [[ -f "${ORBIT_ROOT}/scripts/_auth-check.sh" ]]; then
    cp "${ORBIT_ROOT}/scripts/_auth-check.sh" "tools/_auth-check.sh"
    chmod +x "tools/_auth-check.sh"
  fi

  # Build initial registry
  if declare -F registry_build >/dev/null 2>&1; then
    registry_build "$(pwd)" 2>/dev/null || true
  fi

  echo "Project '$project_name' initialised."
  echo "  orbit.yaml — system config"
  echo "  .orbit/    — state directory"
  echo "  Next: add components to components/ and run 'orbit doctor'"
}
