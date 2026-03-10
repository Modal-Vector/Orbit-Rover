# orbit-docsmith

Document transformation studio for Orbit Rover.

## Context

You are operating inside an Orbit ralph loop. Each invocation is a fresh process
with a fresh context window. You have no memory of prior orbits — your only
continuity is through files on disk and the checkpoint passed to you in the prompt.

## What This Studio Does

Transforms a source document (research paper, spec, raw notes) into a polished
structured document. The decomposer reads the source and creates a task list.
The writer processes one section per orbit until all sections are complete.

## Key Files

- `.orbit/plans/docsmith/tasks.json` — task list created by decomposer
- `output/` — directory where transformed sections are written
- `.orbit/state/section-writer/checkpoint.md` — progress notes between orbits

## Rules

- Complete one section per orbit. Do not attempt multiple.
- Always update tasks.json to mark completed work.
- Write detailed checkpoint notes — future orbits depend on them.
