---
title: Running in Docker
last_updated: 2026-03-13
---

[← Back to Index](index.md)

# Running Orbit Rover in Docker (Recommended)

**Running Orbit in a Docker container is the recommended deployment method.**
Orbit invokes Claude Code with full permissions
(`--dangerously-skip-permissions`) so the agent can operate autonomously within
the orbit loop. This gives the agent unrestricted access to the filesystem and
shell. A container provides isolation from the host system, limiting the blast
radius of any undesirable agent actions — especially important for unattended,
scheduled, or production runs.

The included Dockerfile builds a self-contained image with Orbit Rover and all
dependencies pre-installed (bash, jq, yq, python3, claude-code, opencode, gum,
cron, inotify-tools). It runs as a non-root user, and your project directory is
mounted into the container at runtime.

A `docker-compose.yml` is provided so you don't need to repeat volume mounts,
env files, and port mappings on every command.

## Setup

1. Add your API keys to a `.env` file in the project root (keep this out of
   version control):

   ```
   ANTHROPIC_API_KEY=sk-ant-...
   OPENAI_API_KEY=sk-...
   ```

2. Build the image:

   ```bash
   docker compose build
   ```

## Running Commands

```bash
docker compose run --rm orbit doctor
docker compose run --rm orbit run my-component
docker compose run --rm orbit launch my-mission
```

The compose service passes your `.env` keys automatically and mounts the
current directory into `/workspace`.

## Authentication

### API Keys (recommended)

Add keys to your `.env` file as shown in Setup above. The compose file loads
them automatically — no extra flags needed.

### Interactive Claude Code Login

Claude Code supports OAuth-based login. Open a shell in the container:

```bash
docker compose run --rm --entrypoint bash orbit
```

Then run:

```bash
claude login
```

Credentials are stored in a named Docker volume (`orbit-claude-config`,
mounted at `/home/orbit/.claude`) and persist across container runs.

## Interactive Shell

```bash
docker compose run --rm --entrypoint bash orbit
```

From inside the container:

```bash
orbit doctor          # verify dependencies
orbit status          # check project state
claude --version      # verify claude-code
opencode --version    # verify opencode
```

## Web Dashboard

```bash
docker compose run --rm --service-ports orbit dashboard --web
```

Then open `http://localhost:8777` in your browser. The `--service-ports` flag
is needed so compose maps port 8777 to the host.

## Offline Mode with Ollama

Orbit Rover can run fully offline using Ollama on the host machine. The compose
file is pre-configured to route Ollama traffic to the host — no extra setup
needed if Ollama is running on the default port (11434).

Make sure Ollama is running on your host:

```bash
ollama serve
```

Then run components that use Ollama-backed models as normal:

```bash
docker compose run --rm orbit run my-component
```

The container reaches Ollama via `host.docker.internal:11434`. If Ollama is on
a different port, update `OLLAMA_HOST` in your `.env` file:

```
OLLAMA_HOST=http://host.docker.internal:11500
```

## Watch Mode

```bash
docker compose run --rm orbit watch
```

## Tips

- **The container runs as a non-root user (`orbit`).** Claude Code requires
  non-root invocation, so the Dockerfile creates a dedicated user. All runtime
  commands execute as this user automatically.
- **Don't put API keys in the Dockerfile or image.** Always use the `.env` file.
- **The `.orbit/` state directory** lives inside your mounted project, so state
  persists between container runs automatically.
- **Use `--rm`** (included in the examples) to clean up stopped containers.

[← Back to Index](index.md)
