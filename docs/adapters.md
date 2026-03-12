---
title: Adapters
last_updated: 2026-03-10
---

[← Back to Index](index.md)

# Adapters

Adapters bridge Rover's orbit loop to external AI agent CLIs. Each adapter
translates Rover's invocation parameters into the target CLI's argument format.

**Source:** `lib/adapters/`

## claude-code Adapter

**Source:** `lib/adapters/claude_code.sh`

Invokes the `claude` CLI (Claude Code) as a subprocess.

### Model Mapping

| Rover Alias | Claude Model ID |
|-------------|----------------|
| `sonnet` | `claude-sonnet-4-6` |
| `opus` | `claude-opus-4-6` |
| `haiku` | `claude-haiku-4-5-20251001` |

Unknown aliases are passed through unchanged.

### Invocation

```bash
claude -p <prompt> --output-format json --model <mapped-model> --max-turns <N>
```

When `tools.policy` is `restricted` and tools are assigned:
```bash
claude -p <prompt> --output-format json --model <model> --max-turns <N> \
  --allowedTools <tool1>,<tool2>,...
```

### Output Handling

The adapter parses JSON output from `claude`, trying fields in order:
`.result`, `.text`, `.content`. The extracted text is returned on stdout.

### Subagents

When using `claude-code`, specialist subagent definitions in `.claude/agents/`
are available to the agent via the Agent tool. This allows the main agent to
delegate subtasks (e.g. source evaluation, log analysis) to focused specialists
within a single orbit. See [Studios](studios.md) for the subagents included
with each studio.

## opencode Adapter

**Source:** `lib/adapters/opencode.sh`

Invokes the `opencode` CLI as a subprocess.

### Invocation

```bash
opencode run -p <prompt> -f json -q
```

With model override:
```bash
opencode run -p <prompt> -f json -q --model <model>
```

When `tools.policy` is `restricted` and tools are assigned:
```bash
opencode run -p <prompt> -f json -q --no-auto-tools --tools <tool1>,<tool2>,...
```

### Model Mapping

Models are passed through directly to opencode (no alias mapping).

## Writing a Custom Adapter

Adapters follow a simple contract:

1. Implement a function named `adapter_<name>(prompt, model, max_turns, tools_policy, tools_assigned)`
2. The function receives the rendered prompt as the first argument
3. Write agent output to stdout
4. Exit with 0 on success, non-zero on failure, 124 on timeout
5. Place the file at `lib/adapters/<name>.sh`
6. Reference it in component config as `agent: <name>`

The adapter function is called by `_invoke_adapter()` in the orbit loop, which
dispatches based on the adapter name.

[← Back to Index](index.md)
