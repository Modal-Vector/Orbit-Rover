#!/usr/bin/env bash
set -euo pipefail

# apply-config-patch.sh — Apply a configuration change
# Usage: apply-config-patch.sh <config-file> <patch-file>
# Classification: restricted (requires auth)

# Auth gate
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! bash "${SCRIPT_DIR}/_auth-check.sh"; then
  echo "DENIED: Auth check failed for apply-config-patch" >&2
  exit 1
fi

CONFIG_FILE="${1:-}"
PATCH_FILE="${2:-}"

if [ -z "$CONFIG_FILE" ] || [ -z "$PATCH_FILE" ]; then
  echo "Usage: apply-config-patch.sh <config-file> <patch-file>" >&2
  exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Config file not found: $CONFIG_FILE" >&2
  exit 1
fi

if [ ! -f "$PATCH_FILE" ]; then
  echo "Patch file not found: $PATCH_FILE" >&2
  exit 1
fi

# Backup current config
BACKUP="${CONFIG_FILE}.bak.$(date +%s)"
cp "$CONFIG_FILE" "$BACKUP"
echo "[CONFIG] Backed up $CONFIG_FILE to $BACKUP"

# Apply the patch
if patch -f "$CONFIG_FILE" "$PATCH_FILE" 2>/dev/null; then
  echo "[CONFIG] Patch applied successfully to $CONFIG_FILE"
elif command -v yq >/dev/null 2>&1 && [[ "$CONFIG_FILE" == *.yaml || "$CONFIG_FILE" == *.yml ]]; then
  # Try YAML merge for YAML files
  yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' "$CONFIG_FILE" "$PATCH_FILE" > "${CONFIG_FILE}.tmp"
  mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
  echo "[CONFIG] YAML merge applied to $CONFIG_FILE"
else
  echo "[CONFIG] Patch failed — restoring backup" >&2
  mv "$BACKUP" "$CONFIG_FILE"
  exit 1
fi
