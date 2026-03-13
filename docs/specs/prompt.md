# Prompt Template Spec

Prompt templates are Markdown files with `{variable}` placeholders that get
substituted at runtime. They are the instructions given to the AI agent each
orbit. Templates live in `prompts/` and are referenced by components via the
`prompt:` field.

## Template Variables

These variables are available in every prompt via `{variable_name}` substitution.
Missing variables are left as literal `{name}` text.

| Variable | Content | Source |
|----------|---------|--------|
| `{orbit.n}` | Current orbit number (1-based) | Runtime |
| `{orbit.checkpoint}` | Progress note from previous orbit | `.orbit/state/{component}/checkpoint.md` |
| `{orbit.progress}` | Accumulated operational log from this run | `.orbit/state/{component}/progress.md` |
| `{orbit.max}` | Maximum orbits configured | Component config |
| `{decisions.summary}` | Active decisions for current scope | Learning system |
| `{insights}` | Relevant insights for current scope | Learning system |
| `{feedback.summary}` | Top feedback items for this component | Learning system |
| `{mission.name}` | Current mission name | Runtime (mission context only) |
| `{mission.run_id}` | Unique run identifier | Runtime (mission context only) |
| `{mission.run_dir}` | Run-specific working directory | Runtime (mission context only) |

## Prompt Structure

Every Orbit prompt should follow this structure. Sections can be omitted if they
don't apply, but the ordering should be preserved.

### 1. Title + back-pressure framing

The prompt opens with the component name as a heading, followed by back-pressure
framing that tells the agent it's in a loop and won't exit until work is done.
This prevents the agent from treating each orbit as a one-shot task.

```markdown
# Component Name

You are in a loop. You will not exit this loop until the promise flag is
written. Make genuine progress this orbit or leave accurate notes so the
next orbit can.
```

### 2. Checkpoint injection

Immediately after the framing, inject the previous orbit's checkpoint so the
agent has continuity. On the first orbit this will be empty.

```markdown
Prior progress:
{orbit.checkpoint}
```

### 3. Task instructions

Tell the agent what to do this orbit. Be specific about inputs, actions, and
outputs. If the workflow is task-list driven, tell the agent where to find
the task list and how to mark tasks done.

### 4. Output format

If the deliverable has a specific format (a report, a JSON file, a code
change), describe it here.

### 5. Rules

Constraints on agent behaviour. One task per orbit, ordering requirements,
tools it must not use, etc. Keep rules as a bulleted list — agents follow
short, explicit rules more reliably than prose.

### 6. Learning

Instructions for when the agent should emit insights, feedback, or decisions.
Each XML tag example must be wrapped in instructional text that explains
*when* to emit it — bare tag examples without context are not enough.

### 7. Progress

Instructions for emitting a checkpoint (always) and feedback (when relevant).
This section goes last because it's about wrapping up the orbit.

## XML Tags (Agent Output)

Agents emit these XML tags in their output. The engine parses them after each
orbit and routes them to the appropriate subsystem.

### Checkpoint

Captured from agent output and written to `.orbit/state/{component}/checkpoint.md`.
Injected into the next orbit via `{orbit.checkpoint}`. Only the latest is kept.

```xml
<checkpoint>
- Completed: processed T-003, wrote findings/T-003.md
- Findings: key insight about network partitions
- Next: process T-004 (database replication topic)
</checkpoint>
```

If the agent doesn't emit `<checkpoint>`, the engine takes the last 500 words
of the raw output. Either way, capped at 500 words.

### Progress Notes

Append-only operational log of what happened across orbits in this run. Extracted
from `<progress>` tags and appended to `.orbit/state/{component}/progress.md`
with orbit number headers. Injected into the next orbit via `{orbit.progress}`.
The file is cleared at the start of each component run.

Unlike checkpoint, progress has **no fallback extraction** — if the agent doesn't
emit `<progress>`, nothing is appended. ~200 word soft limit per entry.

```xml
<progress>
- Done: analysed source T-003, wrote findings
- Skipped: T-004 source unavailable (404)
- Failed: distillation script timed out on T-005
</progress>
```

**How to instruct the agent:** Place progress emission instructions in the
"Progress" section alongside the checkpoint:

```markdown
### Progress

Emit a progress note (~200 words) recording what happened this orbit:

<progress>
- Done: what was completed
- Skipped: what was blocked and why
- Failed: what was tried and didn't work
</progress>
```

**How to instruct the agent (checkpoint):** Don't just show the tag — tell the agent *when*
to emit it and what to include. Place this at the end of the prompt in a
"Progress" section:

```markdown
### Progress

Before exiting, emit a checkpoint so the next orbit knows where you left off:

<checkpoint>
- Completed: which task you finished and what was produced
- Findings: key results or observations worth carrying forward
- Next: what the next orbit should work on
</checkpoint>
```

### Feedback

Self-improvement suggestions for the component's prompt. Stored in
`.orbit/learning/feedback/{component}.jsonl`. Surfaced via `{feedback.summary}`.

```xml
<feedback>
The validation step should also check for future-dated entries — this keeps
causing false positives in the compliance report.
</feedback>
```

Vote on existing feedback:
```xml
<vote id="fb-0023" weight="2">Still relevant — recurring issue</vote>
```

**How to instruct the agent:** Tell the agent what kind of observations warrant
feedback and where to emit it relative to the checkpoint:

```markdown
If you notice a process issue, a gap in your instructions, or something that
would make future orbits more effective, report it:

<feedback>What went wrong or could be improved, and why it matters</feedback>
```

### Insights

Operational observations scoped to different levels. Stored in
`.orbit/learning/insights/`. Surfaced via `{insights}`.

```xml
<!-- Project-wide (visible to all components) -->
<insight target="project">
Source APIs rate-limit after 100 requests/hour. Batch requests accordingly.
</insight>

<!-- Mission-scoped (visible to components in this mission) -->
<insight target="mission">
Tasks created in the last sprint tend to have incomplete acceptance criteria.
</insight>

<!-- Component-scoped (visible only to this component) -->
<insight target="component:researcher">
Distilled sources under 2KB usually indicate the fetch script failed silently.
</insight>

<!-- Run-scoped (current run only, not persisted) -->
<insight target="run">
Working on the backup dataset because primary API is down.
</insight>
```

**Scope hierarchy (wider to narrower):** project > mission > component > run

**How to instruct the agent:** Tell the agent what kind of patterns to look for
and at what scope level:

```markdown
If you discover a recurring pattern worth tracking across incidents, emit an
insight:

<insight target="project">Pattern description and its operational impact</insight>

If the pattern is specific to this component's workflow, scope it narrower:

<insight target="component:remediator">Pattern specific to remediation work</insight>
```

### Decisions

Prescriptive choices that constrain future agent behaviour. Stored in
`.orbit/learning/decisions/`. Surfaced via `{decisions.summary}`.

```xml
<!-- Propose a decision -->
<decision title="Use IEC 62304 as SRS structure" target="project">
All SRS sections should follow IEC 62304 section numbering to avoid
reviewer confusion.
</decision>

<!-- Supersede a prior decision -->
<decision title="Switch to TGA template" supersedes="dec-0012" target="project">
TGA reviewers prefer the ARGMD template over raw IEC 62304.
</decision>
```

**Lifecycle:** proposed > accepted > superseded | rejected

**How to instruct the agent:** Only include decision instructions for components
that make architectural or methodological choices. Frame it as a gate:

```markdown
If you make a choice that should bind future orbits (e.g. selecting a
template, choosing an approach over alternatives), propose it as a decision:

<decision title="Short description of the choice" target="project">
What was decided and why. This will be shown to future orbits as a constraint.
</decision>
```

### Tool Requests

Request access to a restricted tool. Processed by the tool governance system.

```xml
<tool_request>
<tool>restart-service</tool>
<justification>Health check shows the API is unresponsive after config patch.
A restart is needed to apply the new configuration.</justification>
</tool_request>
```

**How to instruct the agent:** Only relevant for components with a restricted
tool policy. List the available tools, mark which are restricted, and show how
to request others:

```markdown
### Tool Policy

You are operating under a **restricted** tool policy. You may ONLY use the
tools listed above. If you need a tool that is not assigned, you must request it:

<tool_request>
<tool>name-of-tool</tool>
<justification>Why this tool is needed for the current task</justification>
</tool_request>
```

## Minimal Prompt Example

A complete, self-contained prompt for a generic task worker. All standard
sections are present. Adapt this skeleton for any component.

```markdown
# Worker

You are in a loop. You will not exit this loop until the promise flag is
written. Make genuine progress this orbit or leave accurate notes so the
next orbit can.

Prior progress:
{orbit.checkpoint}

## Task

Read the task list from `.orbit/plans/current/tasks.json`. Find the first
task where `done` is `false`.

1. Read the task description and any prior notes from previous orbits
2. Complete the work described in the task
3. Write output to the location specified in the task's `output` field
4. Mark the task as `done: true` in `tasks.json`

If you cannot complete the task this orbit, leave detailed notes in the
task's `notes` field describing what you tried, what failed, and what the
next orbit should attempt.

## Rules

- Complete exactly ONE task per orbit — do not skip ahead
- Read the full task description before starting work
- If a task depends on output from a previous task, verify that output
  exists before proceeding
- Do not modify tasks other than the one you are working on

## Learning

If you discover a reusable pattern or operational insight while working,
emit an insight so future orbits benefit:

<insight target="component:worker">
Description of the pattern and when it applies
</insight>

If you notice something wrong with these instructions or a way to make
future orbits more effective, report it:

<feedback>What could be improved and why</feedback>

## Progress

Before exiting, emit a checkpoint so the next orbit knows where you left off:

<checkpoint>
- Completed: which task you finished (task ID and summary)
- Output: what was produced and where it was written
- Next: what the next orbit should work on
</checkpoint>
```

## Real-World Example

The full `studios/orbit-fieldops/prompts/remediator.md` prompt. This
demonstrates task-list driven workflow, restricted tool policy, tool request
tags, rules, and progress with checkpoint + feedback + insight tags — all
with instructional framing.

```markdown
# Remediator

You are in a loop. You will not exit this loop until the promise flag is written. Make genuine progress this orbit or leave accurate notes so the next orbit can.

Prior progress:
{orbit.checkpoint}

## Task

Read the task list from `.orbit/plans/fieldops/tasks.json`. Find the first task where `done` is `false`.

Apply the remediation using ONLY the assigned tools:
- `notify-operator` — send notifications to the operator
- `check-health` — check service health endpoints
- `restart-service` — restart a service (restricted, requires approval)
- `apply-config-patch` — apply a configuration change (restricted, requires approval)

1. Execute the remediation tool specified in the task
2. Verify the fix using the task's verification criteria
3. If verification fails, set `"verification_failed": true` on the task and leave notes for the next orbit
4. If verification passes, mark the task as `done: true` in `tasks.json`

### Tool Policy

You are operating under a **restricted** tool policy. You may ONLY use the four tools listed above. If you need a tool that is not assigned, you must request it:

<tool_request>
tool_name: name-of-tool
reason: Why this tool is needed for the current remediation
</tool_request>

### Rules

- Apply exactly ONE fix per orbit
- Always run check-health after applying a fix
- For restricted tools (restart-service, apply-config-patch), ensure notify-operator was called first
- If a fix fails verification, leave detailed notes for the next orbit
- Do NOT attempt to use tools outside your assigned set

### Progress

Before exiting, emit a checkpoint so the next orbit knows where you left off:

<checkpoint>
- Completed: which task you worked on
- Action: what tool was used and what it did
- Verification: health check result
- Next: what the next orbit should do
</checkpoint>

Report on remediation effectiveness:

<feedback>Notes on whether the fix worked, unexpected side effects, or process issues</feedback>

Emit insights for recurring operational patterns:

<insight target="project">Pattern worth tracking across incidents</insight>
```

## Common Mistakes

**Using `${variable}` instead of `{variable}`** — Orbit templates use bare
braces: `{orbit.checkpoint}`, not `${orbit.checkpoint}`. Shell-style `${}` won't
be substituted.

**Forgetting the back-pressure instruction** — Every worker prompt should include
the loop framing: "You are in a loop. You will not exit this loop until..."
Without it, agents may not understand they're in an iterative process.

**Not including `{orbit.checkpoint}`** — Without this, the agent has no
continuity between orbits. Always include it near the top of the prompt.

**XML tags in the prompt template vs agent output** — The template itself should
show example XML tags as instructions for the agent to emit. The engine parses
these tags from agent *output*, not from the template.

**Insight target typos** — `target="component:name"` must match an actual
component name in the registry. The engine warns on unrecognised targets.

**Bare XML tag examples without instructions** — Showing `<feedback>...</feedback>`
without telling the agent *when* to emit it leads to inconsistent usage. Always
wrap tag examples in instructional text like "If you notice a process issue..."
or "Before exiting, emit a checkpoint...".
