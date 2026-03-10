# Orbit Rover — Bash Coding Standards

These standards apply to all code in `lib/`, `cmd/`, and `orbit`.

## Shell Header

Every `.sh` file starts with:
```bash
set -euo pipefail
```

Functions that legitimately return non-zero (e.g. `cascade_is_active`) must be
called with `||` or inside `if` — never bare.

## Atomic Writes

All writes to JSONL files and state files must be atomic:
```bash
local tmp; tmp="$(mktemp)"
echo "$json_line" > "$tmp"
mv "$tmp" "$target"
```
Never append partial JSON. Never write directly to the target path.

## ID Generation

Do not require `uuidgen`. Generate IDs as:
```bash
echo -n "${timestamp}${content}${RANDOM}" | sha256sum | head -c 12
```
Prefix with type: `fb-`, `ins-`, `dec-`, `req-`.

## YAML Parsing

Use `yq` for all YAML access. Fallback to `python3 -c "import yaml, sys; ..."`
if yq is unavailable. Never use sed/awk to parse YAML structure.

## Portability (bash 4+, Linux + macOS)

- `$(command -v tool)` not `which tool`
- `mktemp` not fixed temp paths
- `sleep 0.5` must fall back to `sleep 1` if unsupported
- No bashisms beyond bash 4 (associative arrays are fine)
- Use `date -u +%s` for epoch timestamps (works on both platforms)
- `sha256sum` on Linux, `shasum -a 256` on macOS — wrap in a helper

## Quoting and Variables

- Always double-quote variable expansions: `"$var"`, `"${array[@]}"`
- Use `local` for function-scoped variables
- Use `readonly` for constants

## Unsupported Station Fields

When Rover encounters these in orbit.yaml, warn and continue — never error:
```
resource_pool, inflight, streams, streams.backend, webhooks,
serve, serve.enabled, serve.port, deployment: contained,
deployment: c2, state.backend: postgres
```
Warning format:
```
[ROVER WARN] orbit.yaml: 'webhooks' not supported in Rover (Station feature). Use file sensors as an alternative.
```

## State Directory Layout

All runtime state lives in `.orbit/`:
```
.orbit/state/{component}/checkpoint.md   — latest checkpoint
.orbit/learning/feedback/*.jsonl          — feedback entries
.orbit/learning/insights/*.jsonl          — insight entries
.orbit/learning/decisions/*.jsonl         — decision entries
.orbit/plans/{project}/tasks.json         — project task list
.orbit/cascade/active.json               — cascade block state
```
