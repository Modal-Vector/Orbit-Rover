#!/usr/bin/env bash
set -euo pipefail

# yaml.sh — Low-level YAML helpers using yq
# Dual-path strategy: yq (Go binary) is preferred for speed; python3 + PyYAML
# is the fallback when yq is not installed. Every public function (yaml_get,
# yaml_get_array, yaml_get_map, yaml_exists, yaml_to_json) checks availability
# at call time, so both paths produce identical output for the same input.
# Key handling: dot notation (e.g. "defaults.agent") is split into nested
# traversal by yq natively and by the python helpers via key.split('.').

_yaml_has_yq() {
  command -v yq >/dev/null 2>&1
}

_yaml_has_python() {
  command -v python3 >/dev/null 2>&1
}

# _yaml_python_navigate — shared python logic for key traversal
# Passes file and key as command-line arguments to avoid injection.
_yaml_python_get() {
  python3 - "$1" "$2" <<'PYEOF'
import yaml, sys
file_path, key = sys.argv[1], sys.argv[2]
with open(file_path) as f:
    d = yaml.safe_load(f) or {}
for k in key.split('.'):
    if isinstance(d, dict):
        d = d.get(k)
    else:
        d = None
        break
print('' if d is None else str(d))
PYEOF
}

_yaml_python_get_array() {
  python3 - "$1" "$2" <<'PYEOF'
import yaml, sys
file_path, key = sys.argv[1], sys.argv[2]
with open(file_path) as f:
    d = yaml.safe_load(f) or {}
for k in key.split('.'):
    if isinstance(d, dict):
        d = d.get(k)
    else:
        d = None
        break
if isinstance(d, list):
    for item in d:
        print(item)
PYEOF
}

_yaml_python_get_map() {
  python3 - "$1" "$2" <<'PYEOF'
import yaml, sys
file_path, key = sys.argv[1], sys.argv[2]
with open(file_path) as f:
    d = yaml.safe_load(f) or {}
for k in key.split('.'):
    if isinstance(d, dict):
        d = d.get(k)
    else:
        d = None
        break
if isinstance(d, dict):
    for k in sorted(d.keys()):
        print(k)
PYEOF
}

_yaml_python_exists() {
  python3 - "$1" "$2" <<'PYEOF'
import yaml, sys
file_path, key = sys.argv[1], sys.argv[2]
with open(file_path) as f:
    d = yaml.safe_load(f) or {}
for k in key.split('.'):
    if isinstance(d, dict):
        d = d.get(k)
    else:
        sys.exit(1)
if d is None:
    sys.exit(1)
PYEOF
}

# yaml_get file key — get scalar value
# Key uses dot notation: "defaults.agent"
# Null handling: yq's `// ""` coalesces null to empty string, and the sed
# strip catches the literal "null" output that yq emits for absent keys.
yaml_get() {
  local file="$1" key="$2"
  if _yaml_has_yq; then
    yq e ".${key} // \"\"" "$file" 2>/dev/null | sed 's/^null$//'
  elif _yaml_has_python; then
    _yaml_python_get "$file" "$key"
  else
    echo "[ROVER ERROR] Neither yq nor python3 available for YAML parsing" >&2
    return 1
  fi
}

# yaml_get_array file key — get array as newline-separated values
yaml_get_array() {
  local file="$1" key="$2"
  if _yaml_has_yq; then
    yq e ".${key} // [] | .[]" "$file" 2>/dev/null
  elif _yaml_has_python; then
    _yaml_python_get_array "$file" "$key"
  else
    echo "[ROVER ERROR] Neither yq nor python3 available for YAML parsing" >&2
    return 1
  fi
}

# yaml_get_map file key — get map keys as newline-separated values
yaml_get_map() {
  local file="$1" key="$2"
  if _yaml_has_yq; then
    yq e ".${key} // {} | keys | .[]" "$file" 2>/dev/null
  elif _yaml_has_python; then
    _yaml_python_get_map "$file" "$key"
  else
    echo "[ROVER ERROR] Neither yq nor python3 available for YAML parsing" >&2
    return 1
  fi
}

# yaml_exists file key — test if key exists and is non-null
yaml_exists() {
  local file="$1" key="$2"
  if _yaml_has_yq; then
    local val
    val=$(yq e ".${key}" "$file" 2>/dev/null)
    [[ -n "$val" && "$val" != "null" ]]
  elif _yaml_has_python; then
    _yaml_python_exists "$file" "$key"
  else
    echo "[ROVER ERROR] Neither yq nor python3 available for YAML parsing" >&2
    return 1
  fi
}

# yaml_to_json file — convert full YAML file to JSON (for stage parsing)
# Used by config_load_mission/config_load_module when yq unavailable.
yaml_to_json() {
  local file="$1"
  if _yaml_has_yq; then
    yq e -o=json '.' "$file" 2>/dev/null
  elif _yaml_has_python; then
    python3 - "$file" <<'PYEOF'
import yaml, json, sys
with open(sys.argv[1]) as f:
    d = yaml.safe_load(f) or {}
json.dump(d, sys.stdout)
PYEOF
  else
    echo "[ROVER ERROR] Neither yq nor python3 available for YAML parsing" >&2
    return 1
  fi
}
