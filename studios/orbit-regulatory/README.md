# orbit-regulatory — TGA SaMD Regulatory Studio

Automates TGA SaMD regulatory documentation using Orbit Rover's two-tier
ralph loop pattern.

## Usage

```bash
# Initialise Orbit in this directory
orbit init

# Set up your requirements, risks, and decisions directories
mkdir -p requirements risks decisions regulatory-docs

# Step 1: Plan document generation
orbit launch plan-docs

# Step 2: Generate regulatory documents
orbit launch generate-docs

# For reactive decision capture
orbit watch
# (triggers on decisions/**/*.yaml changes)

# Pre-release verification
orbit launch pre-release-gate

# Monitor progress
orbit status generate-docs
```

## Missions

| Mission | Type | Purpose |
|---------|------|---------|
| plan-docs | Planning | Create document generation task list |
| generate-docs | Implementation | Draft regulatory documents section by section |
| decision-capture | Reactive | Validate and link new design decisions |
| pre-release-gate | Verification | Sequential verification chain + manual approval |

## Components

| Component | Role |
|-----------|------|
| doc-planner | Plans document generation tasks |
| doc-task-decomposer | Breaks sections into atomic drafting tasks |
| doc-drafter | Drafts one regulatory document section per orbit |
| traceability-generator | Generates requirement-risk-implementation trace matrix |
| ddr-validator | Validates design decision record format |
| compliance-linker | Links decisions to requirements and risks |
| regulatory-analyst | Analyses regulatory implications |
| soup-assessor | Assesses Software of Unknown Provenance |
| req-tracker | Tracks requirement implementation/verification status |
| risk-monitor | Monitors risk control implementation |
| verification-planner | Creates verification plans |

## TGA SaMD Context

This studio supports Australian TGA regulatory submissions for Software as a Medical Device:
- IEC 62304 (Software lifecycle)
- IEC 14971 (Risk management)
- TGA Essential Principles
- TGA guidance on software-based medical devices

## Requirements

- bash 4+, jq, yq
- An AI adapter: `claude-code` (default) or `opencode`
