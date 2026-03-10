#!/usr/bin/env bash
set -euo pipefail

# build-trace-excerpt.sh — Build a focused traceability excerpt for the current section
# Creates a subset of the traceability matrix relevant to the current doc task.

TASKS_FILE=".orbit/plans/regulatory/tasks.json"
TRACE_FILE="traceability/matrix.json"
OUTPUT_FILE=".orbit/state/doc-drafter/trace-excerpt.md"

mkdir -p "$(dirname "$OUTPUT_FILE")"

if [ ! -f "$TASKS_FILE" ]; then
  echo "[ORBIT WARN] No tasks file found" >&2
  echo "No traceability data available." > "$OUTPUT_FILE"
  exit 0
fi

TASK=$(jq -r '[.tasks[] | select(.done == false)] | first // empty' "$TASKS_FILE")

if [ -z "$TASK" ]; then
  echo "All tasks complete." > "$OUTPUT_FILE"
  exit 0
fi

TASK_ID=$(echo "$TASK" | jq -r '.id')
SECTION=$(echo "$TASK" | jq -r '.section // empty')

if [ ! -f "$TRACE_FILE" ]; then
  echo "# Traceability Excerpt: ${SECTION:-$TASK_ID}" > "$OUTPUT_FILE"
  echo "" >> "$OUTPUT_FILE"
  echo "No traceability matrix available. Generate with traceability-generator first." >> "$OUTPUT_FILE"
  exit 0
fi

# Extract relevant trace entries
REQ_IDS=$(echo "$TASK" | jq -r '.requirements[]? // empty')
RISK_IDS=$(echo "$TASK" | jq -r '.risks[]? // empty')

{
  echo "# Traceability Excerpt: ${SECTION:-$TASK_ID}"
  echo ""

  if [ -n "$REQ_IDS" ]; then
    echo "## Requirement Traces"
    echo ""
    for req_id in $REQ_IDS; do
      TRACE=$(jq -r --arg id "$req_id" '.entries[]? | select(.requirement == $id) // empty' "$TRACE_FILE" 2>/dev/null || true)
      if [ -n "$TRACE" ]; then
        echo "### ${req_id}"
        echo "$TRACE" | jq -r '"- Implementation: \(.implementation // "pending")\n- Verification: \(.verification // "pending")\n- Status: \(.status // "unknown")"' 2>/dev/null || echo "- _trace data malformed_"
        echo ""
      fi
    done
  fi

  if [ -n "$RISK_IDS" ]; then
    echo "## Risk Control Traces"
    echo ""
    for risk_id in $RISK_IDS; do
      TRACE=$(jq -r --arg id "$risk_id" '.entries[]? | select(.risk == $id) // empty' "$TRACE_FILE" 2>/dev/null || true)
      if [ -n "$TRACE" ]; then
        echo "### ${risk_id}"
        echo "$TRACE" | jq -r '"- Control: \(.control // "pending")\n- Verification: \(.verification // "pending")\n- Status: \(.status // "unknown")"' 2>/dev/null || echo "- _trace data malformed_"
        echo ""
      fi
    done
  fi
} | head -c 10240 > "$OUTPUT_FILE"

echo "[ORBIT INFO] Built trace excerpt for $TASK_ID ($(wc -c < "$OUTPUT_FILE") bytes)"
