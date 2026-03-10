#!/usr/bin/env bash
set -euo pipefail

# flight_rules.sh — Flight rule evaluation for mission safety
# Evaluates conditions against run metrics, enforces warn/abort actions.

# Check flight rules against current metrics
# Returns: 0 = all pass, 2 = abort triggered
flight_rules_check() {
  local rules_json="$1"    # JSON array of rule objects
  local metrics_json="$2"  # JSON object with metric values

  local rule_count
  rule_count=$(echo "$rules_json" | jq 'length')

  local i
  for ((i = 0; i < rule_count; i++)); do
    local rule
    rule=$(echo "$rules_json" | jq -c ".[$i]")

    local name condition on_violation message
    name=$(echo "$rule" | jq -r '.name // "unnamed"')
    condition=$(echo "$rule" | jq -r '.condition // ""')
    on_violation=$(echo "$rule" | jq -r '.on_violation // "warn"')
    message=$(echo "$rule" | jq -r '.message // "Flight rule violated"')

    [[ -z "$condition" ]] && continue

    # Expand metrics.* variables in the condition
    local expanded="$condition"
    expanded=$(_expand_metrics "$expanded" "$metrics_json")

    # Sanitize: after expansion, only allow digits, dots, comparison ops, spaces, minus
    local sanitized
    sanitized=$(echo "$expanded" | sed 's/[^0-9.<>=! -]//g')

    # Evaluate condition using awk for proper numeric comparison
    # Condition is TRUE when rule is satisfied (no violation)
    local violated=false
    if ! echo "$sanitized" | awk '{
      # Parse: operand1 operator operand2
      if ($2 == "<")  exit !($1 < $3)
      if ($2 == ">")  exit !($1 > $3)
      if ($2 == "<=") exit !($1 <= $3)
      if ($2 == ">=") exit !($1 >= $3)
      if ($2 == "==") exit !($1 == $3)
      if ($2 == "!=") exit !($1 != $3)
      exit 1
    }' 2>/dev/null; then
      violated=true
    fi

    if [[ "$violated" == "true" ]]; then
      case "$on_violation" in
        abort)
          orbit_error "Flight rule '${name}' violated: ${message}"
          return 2
          ;;
        warn|*)
          orbit_warn "Flight rule '${name}': ${message}"
          ;;
      esac
    fi
  done

  return 0
}

# Expand metrics.X placeholders with actual values from metrics JSON
_expand_metrics() {
  local condition="$1"
  local metrics_json="$2"

  local result="$condition"

  # Replace known metric vars
  local total_tokens cost_usd duration_seconds orbit_count
  total_tokens=$(echo "$metrics_json" | jq -r '.total_tokens // 0')
  cost_usd=$(echo "$metrics_json" | jq -r '.cost_usd // 0')
  duration_seconds=$(echo "$metrics_json" | jq -r '.duration_seconds // 0')
  orbit_count=$(echo "$metrics_json" | jq -r '.orbit_count // 0')

  result=$(echo "$result" | sed "s/metrics\.total_tokens/${total_tokens}/g")
  result=$(echo "$result" | sed "s/metrics\.cost_usd/${cost_usd}/g")
  result=$(echo "$result" | sed "s/metrics\.duration_seconds/${duration_seconds}/g")
  result=$(echo "$result" | sed "s/metrics\.orbit_count/${orbit_count}/g")

  echo "$result"
}

# Update metrics for a run
metrics_update() {
  local run_id="$1"
  local orbit_count="$2"
  local start_time="$3"   # epoch seconds
  local state_dir="$4"

  local run_dir="${state_dir}/runs/${run_id}"
  mkdir -p "$run_dir"

  local now_epoch
  now_epoch=$(date -u +%s)
  local duration=$((now_epoch - start_time))

  # Read existing metrics or start fresh
  local metrics_file="${run_dir}/metrics.json"
  local total_tokens=0 cost_usd=0
  if [[ -f "$metrics_file" ]]; then
    total_tokens=$(jq -r '.total_tokens // 0' "$metrics_file" 2>/dev/null)
    cost_usd=$(jq -r '.cost_usd // 0' "$metrics_file" 2>/dev/null)
  fi

  local metrics
  metrics=$(jq -nc \
    --argjson total_tokens "$total_tokens" \
    --argjson cost_usd "$cost_usd" \
    --argjson duration_seconds "$duration" \
    --argjson orbit_count "$orbit_count" \
    '{total_tokens: $total_tokens, cost_usd: $cost_usd, duration_seconds: $duration_seconds, orbit_count: $orbit_count}')
  _atomic_write "$metrics_file" "$metrics"
}

# Read metrics for a run
metrics_read() {
  local run_id="$1"
  local state_dir="$2"

  local metrics_file="${state_dir}/runs/${run_id}/metrics.json"
  if [[ -f "$metrics_file" ]]; then
    cat "$metrics_file"
  else
    echo '{"total_tokens":0,"cost_usd":0,"duration_seconds":0,"orbit_count":0}'
  fi
}
