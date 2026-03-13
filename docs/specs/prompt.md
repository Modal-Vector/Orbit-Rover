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
| `{orbit.max}` | Maximum orbits configured | Component config |
| `{decisions.summary}` | Active decisions for current scope | Learning system |
| `{insights}` | Relevant insights for current scope | Learning system |
| `{feedback.summary}` | Top feedback items for this component | Learning system |
| `{mission.name}` | Current mission name | Runtime (mission context only) |
| `{mission.run_id}` | Unique run identifier | Runtime (mission context only) |
| `{mission.run_dir}` | Run-specific working directory | Runtime (mission context only) |

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

### Tool Requests

Request access to a restricted tool. Processed by the tool governance system.

```xml
<tool_request>
<tool>restart-service</tool>
<justification>Health check shows the API is unresponsive after config patch.
A restart is needed to apply the new configuration.</justification>
</tool_request>
```

## Minimal Prompt Example

```markdown
# Worker

You are in a loop. You will not exit this loop until the promise flag is
written. Make genuine progress this orbit or leave accurate notes so the
next orbit can.

Prior progress:
{orbit.checkpoint}

## Task

Read the current task and complete it. Write results to `output/`.

## Progress

<checkpoint>
- What you completed this orbit
- What the next orbit should do
</checkpoint>
```

## Real-World Example

From `studios/orbit-research/prompts/researcher.md` (abbreviated):

```markdown
# Researcher

You are in a loop. You will not exit this loop until the promise flag is
written. Make genuine progress this orbit or leave accurate notes so the
next orbit can.

Prior progress:
{orbit.checkpoint}

## Task

Read the current atomic task from `.orbit/plans/research/atomic/current.json`.
Find the first atomic task where `done` is `false`.

The preflight scripts have already distilled source material. Read:
- `sources/{task-id}/distilled.md` — distilled source content
- `findings/index.md` — findings from previously completed topics

1. Analyse the distilled source material
2. Write findings to `findings/{task-id}.md`
3. Mark the atomic task as `done: true` in `current.json`

### Learning

Emit insights for research methodology improvements:

<insight target="component:researcher">
Observation about source quality or research approach
</insight>

### Progress

<checkpoint>
- Completed: which task you finished
- Findings: key points summary
- Next: what the next orbit should do
</checkpoint>

<feedback>Notes on source quality or process issues</feedback>
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
