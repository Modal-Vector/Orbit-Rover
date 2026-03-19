#!/usr/bin/env bash
set -euo pipefail

# notify-operator.sh — Write operator notification
# Usage: notify-operator.sh <severity> <message>
# Classification: available (no auth required)

SEVERITY="${1:-info}"
shift
MESSAGE="${*:-No message provided}"

NOTIFY_DIR="${ORBIT_RUN_DIR}/notifications"
mkdir -p "$NOTIFY_DIR"

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
NOTIFY_FILE="${NOTIFY_DIR}/$(date +%s)-${SEVERITY}.json"

jq -n --arg severity "$SEVERITY" --arg message "$MESSAGE" \
  --arg timestamp "$TIMESTAMP" --arg component "${ORBIT_COMPONENT:-unknown}" \
  '{severity: $severity, message: $message, component: $component, timestamp: $timestamp}' \
  > "$NOTIFY_FILE"

echo "[NOTIFY] [$SEVERITY] $MESSAGE"
echo "[NOTIFY] Written to $NOTIFY_FILE"
