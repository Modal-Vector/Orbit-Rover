#!/usr/bin/env bash
set -euo pipefail

# extract-req-section.sh — Extract requirements relevant to the current doc section
# Reads the current task from tasks.json and extracts only the requirements
# needed for this specific section, keeping context under 40KB.

TASKS_FILE=".orbit/plans/regulatory/tasks.json"
OUTPUT_FILE=".orbit/state/doc-drafter/req-section.md"

mkdir -p "$(dirname "$OUTPUT_FILE")"

if [ ! -f "$TASKS_FILE" ]; then
  echo "[ORBIT WARN] No tasks file found" >&2
  echo "No requirements available." > "$OUTPUT_FILE"
  exit 0
fi

# Get current task
TASK=$(jq -r '[.tasks[] | select(.done == false)] | first // empty' "$TASKS_FILE")

if [ -z "$TASK" ]; then
  echo "All tasks complete." > "$OUTPUT_FILE"
  exit 0
fi

TASK_ID=$(echo "$TASK" | jq -r '.id')
SECTION=$(echo "$TASK" | jq -r '.section // empty')
REQ_IDS=$(echo "$TASK" | jq -r '.requirements[]? // empty')

REQS_DIR="requirements"
{
  echo "# Requirements for Section: ${SECTION:-$TASK_ID}"
  echo ""

  if [ -n "$REQ_IDS" ]; then
    for req_id in $REQ_IDS; do
      REQ_FILE="${REQS_DIR}/${req_id}.yaml"
      if [ -f "$REQ_FILE" ]; then
        echo "## ${req_id}"
        cat "$REQ_FILE"
        echo ""
      elif [ -f "${REQS_DIR}/${req_id}.md" ]; then
        echo "## ${req_id}"
        cat "${REQS_DIR}/${req_id}.md"
        echo ""
      else
        echo "## ${req_id}"
        echo "_Reference not found_"
        echo ""
      fi
    done
  else
    echo "No specific requirements mapped to this section."
  fi
} | head -c 40960 > "$OUTPUT_FILE"

echo "[ORBIT INFO] Extracted requirements for $TASK_ID to $OUTPUT_FILE ($(wc -c < "$OUTPUT_FILE") bytes)"
