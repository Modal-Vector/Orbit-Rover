# Contributing to Orbit Rover

Thanks for your interest in contributing to Orbit Rover! This guide covers
everything you need to get started.

## Reporting Bugs

Open a [GitHub Issue](https://github.com/Modal-Vector/Orbit-Rover/issues/new?template=bug_report.md)
with steps to reproduce, expected vs actual behaviour, and the output of
`./orbit doctor`.

## Submitting Changes

1. Fork the repository
2. Create a feature branch from `main`
3. Make your changes
4. Run `bats tests/` and ensure all tests pass
5. Submit a pull request against `main`

Keep PRs focused — one feature or fix per PR.

## Running Tests

Tests use [bats](https://github.com/bats-core/bats-core) (Bash Automated
Testing System). The test helpers are included in `tests/helpers/`.

```bash
# Run the full suite (331 tests)
bats tests/

# Run a specific phase
bats tests/phase1-core.bats

# Run a single test by name
bats tests/phase1-core.bats --filter "deadlock detection"
```

All changes must pass the full test suite before merging.

## Coding Standards

**Bash 4+ on Linux and macOS.** Use `$(command -v tool)` not `which`. Use
`mktemp` not fixed temp paths.

**Error handling:** Use `set -euo pipefail` at the top of each lib file.
Functions that may return non-zero (e.g. `cascade_is_active`) must be called
with `||` or inside `if`.

**Atomic writes:** All writes to JSONL and state files must be atomic — write
to a `.tmp` file, then `mv` to the target. Never append partial JSON.

**ID generation:** Do not require `uuidgen`. Generate IDs as:
```bash
echo -n "${timestamp}${content}${RANDOM}" | sha256sum | head -c 12
```
Prefix with type: `fb-`, `ins-`, `dec-`, `req-`.

**YAML parsing:** Use `yq` for all YAML access. If yq is unavailable, fall back
to `python3 -c "import yaml, sys; ..."`. Never use sed/awk on YAML structure.

**No compiled runtimes.** Rover is pure bash. No Python (except YAML fallback
and web dashboard), no Node, no Go.

## Project Layout

```
lib/        Core engine (orbit loop, config, sensors, learning, tools)
cmd/        CLI subcommands
tests/      bats test suite (phase1-8)
docs/       User-facing documentation
studios/    Example projects
```

See `docs/architecture.md` for the full design.

## Claude Code Development Mode

If you use [Claude Code](https://claude.com/claude-code), Orbit Rover includes
a development configuration. The root `CLAUDE.md` contains **runtime**
instructions (used when orbit invokes Claude as an agent). To switch to
**development** mode with coding standards, architecture invariants, and test
requirements:

```bash
# Activate development mode
mv CLAUDE.md CLAUDE.md.orbit
mv CONTRIBUTING.md CLAUDE.md

# When done, restore runtime mode
mv CLAUDE.md CONTRIBUTING.md
mv CLAUDE.md.orbit CLAUDE.md
```

## License

By contributing, you agree that your contributions will be licensed under the
Apache License 2.0.
