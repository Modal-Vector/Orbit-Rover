#!/usr/bin/env bash
set -euo pipefail

# check-ddr-format.sh — Validate DDR (Design Decision Record) format
# Checks that decision YAML files have required fields.

DECISIONS_DIR="decisions"
REPORT_FILE=".orbit/state/ddr-validator/format-check.json"

mkdir -p "$(dirname "$REPORT_FILE")"

if [ ! -d "$DECISIONS_DIR" ]; then
  echo "[ORBIT WARN] No decisions directory found" >&2
  echo '{"valid": true, "checked": 0, "errors": []}' > "$REPORT_FILE"
  exit 0
fi

ERRORS="[]"
CHECKED=0

for ddr_file in "$DECISIONS_DIR"/**/*.yaml "$DECISIONS_DIR"/*.yaml; do
  [ ! -f "$ddr_file" ] && continue
  CHECKED=$((CHECKED + 1))

  BASENAME=$(basename "$ddr_file")

  # Check required fields
  for field in id title status rationale; do
    if ! yq -e ".$field" "$ddr_file" >/dev/null 2>&1; then
      ERRORS=$(echo "$ERRORS" | jq --arg file "$BASENAME" --arg field "$field" \
        '. + [{"file": $file, "error": ("missing required field: " + $field)}]')
    fi
  done
done

VALID="true"
if [ "$(echo "$ERRORS" | jq 'length')" -gt 0 ]; then
  VALID="false"
fi

jq -n --argjson valid "$VALID" --argjson checked "$CHECKED" --argjson errors "$ERRORS" \
  '{valid: $valid, checked: $checked, errors: $errors}' > "$REPORT_FILE"

echo "[ORBIT INFO] DDR format check: $CHECKED files, $(echo "$ERRORS" | jq 'length') errors"
