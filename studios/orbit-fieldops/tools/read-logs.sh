#!/usr/bin/env bash
set -euo pipefail

# read-logs.sh — Read specified log files
# Usage: read-logs.sh <log-file-path> [--tail N]
# Classification: available (no auth required)

LOG_FILE="${1:-}"
TAIL_LINES=""

if [ -z "$LOG_FILE" ]; then
  echo "Usage: read-logs.sh <log-file-path> [--tail N]" >&2
  exit 1
fi

shift
while [ $# -gt 0 ]; do
  case "$1" in
    --tail) TAIL_LINES="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [ ! -f "$LOG_FILE" ]; then
  echo "Log file not found: $LOG_FILE" >&2
  exit 1
fi

if [ -n "$TAIL_LINES" ]; then
  tail -n "$TAIL_LINES" "$LOG_FILE"
else
  cat "$LOG_FILE"
fi
