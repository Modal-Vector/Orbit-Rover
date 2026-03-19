# orbit-research

Multi-faceted topic research studio. Plans a research agenda, investigates
sources topic by topic, then writes findings into polished sections.

## Specialist Subagents

Use these via the Agent tool when working in this studio.

| Agent | When to spawn | What it returns |
|-------|---------------|-----------------|
| `source-evaluator` | Before committing time to analyse a source — pass it a URL or `{run-dir}/sources/{id}/distilled.md` | A scored evaluation (authority, currency, depth, relevance out of 20) with a PROCEED / CAUTION / SKIP recommendation |
| `synthesis-validator` | After multiple findings exist, before writing sections — point it at `{run-dir}/findings/` | A validation report flagging contradictions, unsupported claims, coverage gaps, and terminology drift |
