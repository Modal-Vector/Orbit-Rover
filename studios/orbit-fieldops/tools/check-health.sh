#!/usr/bin/env bash
set -euo pipefail

# check-health.sh — Check service health endpoints
# Usage: check-health.sh <service-name> [--endpoint URL]
# Classification: available (no auth required)

SERVICE="${1:-}"
ENDPOINT=""

if [ -z "$SERVICE" ]; then
  echo "Usage: check-health.sh <service-name> [--endpoint URL]" >&2
  exit 1
fi

shift
while [ $# -gt 0 ]; do
  case "$1" in
    --endpoint) ENDPOINT="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Default endpoint pattern
if [ -z "$ENDPOINT" ]; then
  ENDPOINT="http://localhost:8080/health"
fi

echo "[HEALTH] Checking $SERVICE at $ENDPOINT"

RESULT_DIR="${ORBIT_RUN_DIR}/state/remediator"
mkdir -p "$RESULT_DIR"

if curl -sf --max-time 10 "$ENDPOINT" > /dev/null 2>&1; then
  STATUS="healthy"
  echo "[HEALTH] $SERVICE: healthy"
else
  STATUS="unhealthy"
  echo "[HEALTH] $SERVICE: unhealthy" >&2
fi

# Write result for postflight validation
jq -n --arg service "$SERVICE" --arg status "$STATUS" \
  --arg checked_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{service: $service, status: $status, checked_at: $checked_at}' \
  > "${RESULT_DIR}/last-health-check.json"
