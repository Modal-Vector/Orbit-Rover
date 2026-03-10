#!/usr/bin/env bash
set -euo pipefail

# extract-risk-controls.sh — Extract risk entries and controls relevant to current section
# Reads the current task and extracts only relevant RISK entries.

TASKS_FILE=".orbit/plans/regulatory/tasks.json"
OUTPUT_FILE=".orbit/state/doc-drafter/risk-controls.md"

mkdir -p "$(dirname "$OUTPUT_FILE")"

if [ ! -f "$TASKS_FILE" ]; then
  echo "[ORBIT WARN] No tasks file found" >&2
  echo "No risk controls available." > "$OUTPUT_FILE"
  exit 0
fi

TASK=$(jq -r '[.tasks[] | select(.done == false)] | first // empty' "$TASKS_FILE")

if [ -z "$TASK" ]; then
  echo "All tasks complete." > "$OUTPUT_FILE"
  exit 0
fi

TASK_ID=$(echo "$TASK" | jq -r '.id')
SECTION=$(echo "$TASK" | jq -r '.section // empty')
RISK_IDS=$(echo "$TASK" | jq -r '.risks[]? // empty')

RISKS_DIR="risks"
{
  echo "# Risk Controls for Section: ${SECTION:-$TASK_ID}"
  echo ""

  if [ -n "$RISK_IDS" ]; then
    for risk_id in $RISK_IDS; do
      RISK_FILE="${RISKS_DIR}/${risk_id}.yaml"
      if [ -f "$RISK_FILE" ]; then
        echo "## ${risk_id}"
        cat "$RISK_FILE"
        echo ""
      elif [ -f "${RISKS_DIR}/${risk_id}.md" ]; then
        echo "## ${risk_id}"
        cat "${RISKS_DIR}/${risk_id}.md"
        echo ""
      else
        echo "## ${risk_id}"
        echo "_Risk entry not found_"
        echo ""
      fi
    done
  else
    echo "No specific risks mapped to this section."
  fi
} | head -c 40960 > "$OUTPUT_FILE"

echo "[ORBIT INFO] Extracted risk controls for $TASK_ID to $OUTPUT_FILE ($(wc -c < "$OUTPUT_FILE") bytes)"
