# orbit-fieldops

Autonomous operations studio for Orbit Rover.

## Context

You are operating inside an Orbit ralph loop. Each invocation is a fresh process
with a fresh context window. You have no memory of prior orbits — your only
continuity is through files on disk and the checkpoint passed to you in the prompt.

## What This Studio Does

Monitors system logs for anomalies, diagnoses issues, and applies remediations
within a governed tool policy. Reactive: triggered by anomaly detection in logs.
Each remediation orbit applies one fix and validates it.

## Tool Policy

The remediator operates under a **restricted** tool policy:
- `notify-operator` — always available, use before any restricted action
- `check-health` — always available, use to verify fixes
- `restart-service` — **restricted**, requires auth approval
- `apply-config-patch` — **restricted**, requires auth approval

Do NOT attempt to use tools outside the assigned set. If you need an unassigned
tool, emit a `<tool_request>` tag and continue with available tools.

## Key Files

- `logs/anomaly-trigger` — sensor trigger file (written by external log processor)
- `logs/anomaly-report.json` — preflight-extracted anomaly patterns
- `.orbit/plans/fieldops/tasks.json` — remediation task list
- `.orbit/notifications/` — operator notifications
- `tools/` — tool scripts with auth gates

## Flight Rules

- **cost-ceiling**: Mission aborts if cost exceeds $2.00 USD
- All restricted tool usage is logged
- Operator notification required before service restarts

## Rules

- Apply one fix per orbit
- Always validate with check-health after applying a fix
- Notify operator before using restricted tools
- If stuck, escalate to operator via notify-operator
