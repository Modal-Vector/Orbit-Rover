#!/usr/bin/env bash
set -euo pipefail

# fetch-source.sh — Fetch raw content from the current task's source URL
# Reads the current task from tasks.json and downloads the source content.

TASKS_FILE="${ORBIT_RUN_DIR:-.orbit}/plans/sentinel/tasks.json"

if [ ! -f "$TASKS_FILE" ]; then
  echo "[ORBIT WARN] No tasks file found at $TASKS_FILE" >&2
  exit 0
fi

# Find the first incomplete task
TASK=$(jq -r '[.tasks[] | select(.done == false)] | first // empty' "$TASKS_FILE")

if [ -z "$TASK" ]; then
  echo "[ORBIT INFO] All tasks complete" >&2
  exit 0
fi

TASK_ID=$(echo "$TASK" | jq -r '.id')
SOURCE_URL=$(echo "$TASK" | jq -r '.source_url // empty')

if [ -z "$SOURCE_URL" ]; then
  echo "[ORBIT WARN] No source_url for task $TASK_ID" >&2
  exit 0
fi

# Create output directory
OUTPUT_DIR="${ORBIT_RUN_DIR}/sources/${TASK_ID}"
mkdir -p "$OUTPUT_DIR"

# Fetch the source content
echo "[ORBIT INFO] Fetching $SOURCE_URL for task $TASK_ID"
if curl -sL --max-time 30 --max-filesize 5242880 -o "${OUTPUT_DIR}/raw.html" "$SOURCE_URL" 2>/dev/null; then
  echo "[ORBIT INFO] Saved to ${OUTPUT_DIR}/raw.html"
else
  echo "[ORBIT WARN] Failed to fetch $SOURCE_URL — creating empty placeholder" >&2
  echo "<!-- fetch failed -->" > "${OUTPUT_DIR}/raw.html"
fi
