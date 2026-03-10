#!/usr/bin/env bash
set -euo pipefail

# extract-anomalies.sh — Parse system logs and extract anomaly patterns
# Reads log files from logs/ directory and produces a structured anomaly report.

LOG_DIR="logs"
OUTPUT_FILE="${LOG_DIR}/anomaly-report.json"

if [ ! -d "$LOG_DIR" ]; then
  echo "[ORBIT WARN] No logs directory found" >&2
  mkdir -p "$LOG_DIR"
  echo '{"anomalies": [], "generated_at": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' > "$OUTPUT_FILE"
  exit 0
fi

# Collect all log files
LOG_FILES=$(find "$LOG_DIR" -name '*.log' -type f 2>/dev/null || true)

if [ -z "$LOG_FILES" ]; then
  echo "[ORBIT INFO] No log files found in $LOG_DIR" >&2
  echo '{"anomalies": [], "generated_at": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' > "$OUTPUT_FILE"
  exit 0
fi

# Extract anomaly patterns using common indicators
ANOMALIES="[]"
ANOMALY_COUNT=0

for logfile in $LOG_FILES; do
  BASENAME=$(basename "$logfile")

  # Look for error patterns
  while IFS= read -r line; do
    ANOMALY_COUNT=$((ANOMALY_COUNT + 1))
    ESCAPED_LINE=$(echo "$line" | jq -Rs '.')
    ANOMALIES=$(echo "$ANOMALIES" | jq --arg id "A-$(printf '%03d' $ANOMALY_COUNT)" \
      --arg src "$BASENAME" \
      --arg line "$line" \
      '. + [{"id": $id, "source": $src, "pattern": $line, "severity": "medium"}]')
  done < <(grep -iE '(error|critical|fatal|oom|timeout|refused|denied|exception|panic|segfault)' "$logfile" 2>/dev/null | tail -50 || true)
done

# Write structured report
{
  echo "$ANOMALIES" | jq '{
    anomalies: .,
    total_count: (. | length),
    generated_at: "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
  }'
} > "${OUTPUT_FILE}.tmp"

mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"

echo "[ORBIT INFO] Extracted $(echo "$ANOMALIES" | jq '. | length') anomalies to $OUTPUT_FILE"
