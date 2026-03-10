# orbit-regulatory

TGA SaMD regulatory documentation studio for Orbit Rover.

## Context

You are operating inside an Orbit ralph loop. Each invocation is a fresh process
with a fresh context window. You have no memory of prior orbits — your only
continuity is through files on disk and the checkpoint passed to you in the prompt.

## What This Studio Does

Automates TGA SaMD (Therapeutic Goods Administration, Software as a Medical Device)
regulatory documentation, traceability maintenance, and compliance evidence collection.
Uses a two-tier pattern for document generation and reactive single-tier for decision capture.

## TGA SaMD Domain

This studio operates in the Australian TGA regulatory framework for SaMD:
- IEC 62304 (Software lifecycle processes)
- IEC 14971 (Risk management for medical devices)
- TGA Essential Principles
- TGA guidance on software-based medical devices

All generated documents must reference applicable standards and maintain full traceability.

## Missions

1. **decision-capture** — Reactive: triggers on `decisions/**/*.yaml` changes. Validates DDR format, links compliance, analyses regulatory impact.
2. **pre-release-gate** — Sequential verification chain with manual approval gate (120h, default reject).
3. **plan-docs** — Planning tier: creates document generation task list respecting 40KB context budget.
4. **generate-docs** — Implementation tier: gathers traceability, decomposes tasks, drafts sections (one per orbit), manual review gate.

## Key Directories

- `requirements/` — requirement definitions (REQ-NNN)
- `risks/` — risk entries and controls (RISK-NNN)
- `decisions/` — design decision records (DDR-NNN)
- `regulatory-docs/` — generated regulatory documents
- `traceability/` — traceability matrix
- `verification/` — verification plans and evidence

## Preflight Pipeline (doc-drafter)

Scripts extract only the slice needed for each section:
1. `scripts/extract-req-section.sh` — requirements for current section
2. `scripts/extract-risk-controls.sh` — risk controls for current section
3. `scripts/build-trace-excerpt.sh` — focused trace excerpt (<10KB)

## Rules

- All documents must reference applicable TGA/IEC clauses
- Maintain full traceability: requirement → design → implementation → verification
- Context budget: each orbit's input must stay under 40KB
- Regulatory documents require qualified-person review (manual gate)
