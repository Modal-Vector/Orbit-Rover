#!/usr/bin/env bash
set -euo pipefail

# validate-fix.sh — Post-fix health check
# Runs after each remediation orbit to verify system health.

HEALTH_STATUS=0

# Check if health check endpoint results exist
HEALTH_FILE="${ORBIT_RUN_DIR}/state/remediator/last-health-check.json"

if [ -f "$HEALTH_FILE" ]; then
  STATUS=$(jq -r '.status // "unknown"' "$HEALTH_FILE" 2>/dev/null || echo "unknown")
  if [ "$STATUS" = "healthy" ]; then
    echo "[ORBIT INFO] Post-fix health check: PASSED"
  else
    echo "[ORBIT WARN] Post-fix health check: $STATUS" >&2
    HEALTH_STATUS=1
  fi
else
  echo "[ORBIT INFO] No health check results found — skipping validation"
fi

# Check tasks for any failed verifications
TASKS_FILE="${ORBIT_RUN_DIR:-.orbit}/plans/fieldops/tasks.json"
if [ -f "$TASKS_FILE" ]; then
  FAILED=$(jq '[.tasks[] | select(.done == true and .verification_failed == true)] | length' "$TASKS_FILE" 2>/dev/null || echo "0")
  if [ "$FAILED" -gt 0 ]; then
    echo "[ORBIT WARN] $FAILED task(s) have failed verification" >&2
    HEALTH_STATUS=1
  fi
fi

exit $HEALTH_STATUS
