#!/usr/bin/env bash
set -euo pipefail

# check-refs-exist.sh — Verify that cross-references in decisions exist
# Checks that referenced requirements, risks, and components actually exist.

DECISIONS_DIR="decisions"
REPORT_FILE=".orbit/state/compliance-linker/ref-check.json"

mkdir -p "$(dirname "$REPORT_FILE")"

if [ ! -d "$DECISIONS_DIR" ]; then
  echo '{"valid": true, "checked": 0, "missing_refs": []}' > "$REPORT_FILE"
  exit 0
fi

MISSING="[]"
CHECKED=0

for ddr_file in "$DECISIONS_DIR"/**/*.yaml "$DECISIONS_DIR"/*.yaml; do
  [ ! -f "$ddr_file" ] && continue
  CHECKED=$((CHECKED + 1))

  BASENAME=$(basename "$ddr_file")

  # Check requirement references
  REQS=$(yq -r '.requirements[]? // empty' "$ddr_file" 2>/dev/null || true)
  for req in $REQS; do
    if [ ! -f "requirements/${req}.yaml" ] && [ ! -f "requirements/${req}.md" ]; then
      MISSING=$(echo "$MISSING" | jq --arg file "$BASENAME" --arg ref "$req" \
        '. + [{"file": $file, "ref_type": "requirement", "ref": $ref}]')
    fi
  done

  # Check risk references
  RISKS=$(yq -r '.risks[]? // empty' "$ddr_file" 2>/dev/null || true)
  for risk in $RISKS; do
    if [ ! -f "risks/${risk}.yaml" ] && [ ! -f "risks/${risk}.md" ]; then
      MISSING=$(echo "$MISSING" | jq --arg file "$BASENAME" --arg ref "$risk" \
        '. + [{"file": $file, "ref_type": "risk", "ref": $ref}]')
    fi
  done
done

VALID="true"
if [ "$(echo "$MISSING" | jq 'length')" -gt 0 ]; then
  VALID="false"
fi

jq -n --argjson valid "$VALID" --argjson checked "$CHECKED" --argjson missing "$MISSING" \
  '{valid: $valid, checked: $checked, missing_refs: $missing}' > "$REPORT_FILE"

echo "[ORBIT INFO] Reference check: $CHECKED files, $(echo "$MISSING" | jq 'length') missing refs"
