#!/usr/bin/env bash
set -euo pipefail

# watch_cmd.sh — orbit watch subcommand
# Delegates to watch_start.

cmd_watch() {
  watch_start "$(pwd)"
}
