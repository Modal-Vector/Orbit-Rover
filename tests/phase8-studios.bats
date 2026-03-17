#!/usr/bin/env bats

load helpers/bats-support/load
load helpers/bats-assert/load

# Common setup
setup() {
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  STUDIOS_DIR="$PROJECT_ROOT/studios"
}

# ============================================================
# Helper functions
# ============================================================

# Check that a YAML file parses with yq
yaml_valid() {
  yq '.' "$1" >/dev/null 2>&1
}

# Get a value from YAML
yaml_get() {
  yq -r "$2" "$1"
}

# ============================================================
# All studios: YAML parsing
# ============================================================

@test "studios: all YAML files parse with yq" {
  local failures=()
  while IFS= read -r f; do
    if ! yaml_valid "$f"; then
      failures+=("$f")
    fi
  done < <(find "$STUDIOS_DIR" -name '*.yaml' -type f)

  if [ ${#failures[@]} -gt 0 ]; then
    echo "Failed to parse: ${failures[*]}" >&2
    return 1
  fi
}

# ============================================================
# All studios: orbit.yaml structure
# ============================================================

@test "studios: every orbit.yaml has system/version/defaults" {
  for studio in "$STUDIOS_DIR"/orbit-*/; do
    local config="$studio/orbit.yaml"
    [ -f "$config" ] || { echo "Missing: $config" >&2; return 1; }

    run yaml_get "$config" '.system'
    assert_output "orbit"

    run yaml_get "$config" '.version'
    assert_output "1"

    run yaml_get "$config" '.defaults.agent'
    refute_output "null"
  done
}

# ============================================================
# All studios: component-mission cross-reference
# ============================================================

@test "studios: every component referenced in missions exists" {
  for studio in "$STUDIOS_DIR"/orbit-*/; do
    [ -d "$studio/missions" ] || continue
    local studio_name
    studio_name=$(basename "$studio")

    for mission_file in "$studio"/missions/*.yaml; do
      [ -f "$mission_file" ] || continue
      local mission_name
      mission_name=$(basename "$mission_file" .yaml)

      # Extract component names from stages (skip manual gates)
      local components
      components=$(yq -r '.stages[]? | select(.type != "manual") | .component // empty' "$mission_file" 2>/dev/null || true)

      for comp in $components; do
        [ -z "$comp" ] && continue
        local comp_file="$studio/components/${comp}/${comp}.yaml"
        if [ ! -f "$comp_file" ]; then
          echo "FAIL: $studio_name/$mission_name references component '$comp' but $comp_file does not exist" >&2
          return 1
        fi
      done
    done
  done
}

# ============================================================
# All studios: prompt file references
# ============================================================

@test "studios: every prompt file referenced in components exists" {
  for studio in "$STUDIOS_DIR"/orbit-*/; do
    [ -d "$studio/components" ] || continue
    local studio_name
    studio_name=$(basename "$studio")

    for comp_file in "$studio"/components/*/*.yaml; do
      [ -f "$comp_file" ] || continue
      local comp_name
      comp_name=$(basename "$comp_file" .yaml)

      local prompt_path
      prompt_path=$(yq -r '.prompt // ""' "$comp_file")
      [ -z "$prompt_path" ] && continue

      if [ ! -f "$studio/$prompt_path" ]; then
        echo "FAIL: $studio_name/$comp_name references prompt '$prompt_path' but file does not exist" >&2
        return 1
      fi
    done
  done
}

# ============================================================
# All studios: preflight/postflight scripts exist and executable
# ============================================================

@test "studios: every preflight/postflight script exists and is executable" {
  for studio in "$STUDIOS_DIR"/orbit-*/; do
    [ -d "$studio/components" ] || continue
    local studio_name
    studio_name=$(basename "$studio")

    for comp_file in "$studio"/components/*/*.yaml; do
      [ -f "$comp_file" ] || continue
      local comp_name
      comp_name=$(basename "$comp_file" .yaml)

      # Check preflight scripts
      local preflights
      preflights=$(yq -r '.preflight[]? // empty' "$comp_file" 2>/dev/null || true)
      for script in $preflights; do
        [ -z "$script" ] && continue
        local script_path="$studio/$script"
        if [ ! -f "$script_path" ]; then
          echo "FAIL: $studio_name/$comp_name preflight '$script' does not exist" >&2
          return 1
        fi
        if [ ! -x "$script_path" ]; then
          echo "FAIL: $studio_name/$comp_name preflight '$script' is not executable" >&2
          return 1
        fi
      done

      # Check postflight scripts
      local postflights
      postflights=$(yq -r '.postflight[]? // empty' "$comp_file" 2>/dev/null || true)
      for script in $postflights; do
        [ -z "$script" ] && continue
        local script_path="$studio/$script"
        if [ ! -f "$script_path" ]; then
          echo "FAIL: $studio_name/$comp_name postflight '$script' does not exist" >&2
          return 1
        fi
        if [ ! -x "$script_path" ]; then
          echo "FAIL: $studio_name/$comp_name postflight '$script' is not executable" >&2
          return 1
        fi
      done
    done
  done
}

# ============================================================
# All studios: prompts contain {orbit.checkpoint}
# ============================================================

@test "studios: every prompt contains {orbit.checkpoint}" {
  local failures=()
  for studio in "$STUDIOS_DIR"/orbit-*/; do
    [ -d "$studio/components" ] || continue
    local studio_name
    studio_name=$(basename "$studio")

    for prompt_file in "$studio"/components/*/*.md; do
      [ -f "$prompt_file" ] || continue
      if ! grep -q '{orbit.checkpoint}' "$prompt_file"; then
        failures+=("$studio_name/$(basename "$prompt_file")")
      fi
    done
  done

  if [ ${#failures[@]} -gt 0 ]; then
    echo "Missing {orbit.checkpoint}: ${failures[*]}" >&2
    return 1
  fi
}

# ============================================================
# All studios: worker prompts contain back-pressure text
# ============================================================

@test "studios: worker prompts contain back-pressure instruction" {
  local failures=()
  for studio in "$STUDIOS_DIR"/orbit-*/; do
    [ -d "$studio/components" ] || continue
    local studio_name
    studio_name=$(basename "$studio")

    for prompt_file in "$studio"/components/*/*.md; do
      [ -f "$prompt_file" ] || continue
      if ! grep -q 'You are in a loop' "$prompt_file"; then
        failures+=("$studio_name/$(basename "$prompt_file")")
      fi
    done
  done

  if [ ${#failures[@]} -gt 0 ]; then
    echo "Missing back-pressure text: ${failures[*]}" >&2
    return 1
  fi
}

# ============================================================
# All studios: orbit_exit conditions contain jq
# ============================================================

@test "studios: orbit_exit conditions use jq" {
  for studio in "$STUDIOS_DIR"/orbit-*/; do
    [ -d "$studio/missions" ] || continue
    local studio_name
    studio_name=$(basename "$studio")

    for mission_file in "$studio"/missions/*.yaml; do
      [ -f "$mission_file" ] || continue
      local mission_name
      mission_name=$(basename "$mission_file" .yaml)

      # Extract orbit_exit conditions
      local conditions
      conditions=$(yq -r '.stages[]? | .orbit_exit.condition // empty' "$mission_file" 2>/dev/null || true)
      [ -z "$conditions" ] && continue

      if ! echo "$conditions" | grep -q 'jq'; then
        echo "FAIL: $studio_name/$mission_name orbit_exit condition does not use jq" >&2
        return 1
      fi
    done
  done
}

# ============================================================
# All studios: CLAUDE.md and README.md exist
# ============================================================

@test "studios: every studio has CLAUDE.md" {
  for studio in "$STUDIOS_DIR"/orbit-*/; do
    local studio_name
    studio_name=$(basename "$studio")
    if [ ! -f "$studio/CLAUDE.md" ]; then
      echo "FAIL: $studio_name missing CLAUDE.md" >&2
      return 1
    fi
  done
}

@test "studios: every studio has README.md" {
  for studio in "$STUDIOS_DIR"/orbit-*/; do
    local studio_name
    studio_name=$(basename "$studio")
    if [ ! -f "$studio/README.md" ]; then
      echo "FAIL: $studio_name missing README.md" >&2
      return 1
    fi
  done
}

# ============================================================
# Research-specific tests (formerly scholar)
# ============================================================

@test "research: has three missions (plan, research, and write)" {
  [ -f "$STUDIOS_DIR/orbit-research/missions/plan.yaml" ]
  [ -f "$STUDIOS_DIR/orbit-research/missions/research.yaml" ]
  [ -f "$STUDIOS_DIR/orbit-research/missions/write.yaml" ]
}

@test "research: research mission has weekly cron" {
  local mission="$STUDIOS_DIR/orbit-research/missions/research.yaml"
  run yq -r '.sensors.schedule.cron' "$mission"
  assert_output '0 8 * * 1'
}

@test "research: orbit.yaml.local variant exists with opencode" {
  local variant="$STUDIOS_DIR/orbit-research/orbit.yaml.local"
  [ -f "$variant" ]
  run yq -r '.defaults.agent' "$variant"
  assert_output "opencode"

  run yq -r '.defaults.model' "$variant"
  assert_output "ollama/llama3.2"
}

@test "research: researcher has preflight scripts" {
  local comp="$STUDIOS_DIR/orbit-research/components/researcher/researcher.yaml"
  run yq -r '.preflight[0]' "$comp"
  assert_output "scripts/distil-sources.sh"

  run yq -r '.preflight[1]' "$comp"
  assert_output "scripts/extract-findings.sh"
}

@test "research: research mission has orbits_to decompose" {
  local mission="$STUDIOS_DIR/orbit-research/missions/research.yaml"
  run yq -r '.stages[] | select(.name == "investigate") | .orbits_to' "$mission"
  assert_output "decompose"

  run yq -r '.stages[] | select(.name == "investigate") | .max_orbits' "$mission"
  assert_output "200"
}

@test "research: section-decomposer delivers write-tasks.json" {
  local comp="$STUDIOS_DIR/orbit-research/components/section-decomposer/section-decomposer.yaml"
  run yq -r '.delivers[0]' "$comp"
  assert_output "{mission.run_dir}/plans/research/write-tasks.json"
}

@test "research: section-writer has deadlock_threshold 5" {
  local comp="$STUDIOS_DIR/orbit-research/components/section-writer/section-writer.yaml"
  run yq -r '.orbits.deadlock.threshold' "$comp"
  assert_output "5"
}

@test "research: write mission has decompose and write stages with orbits_to" {
  local mission="$STUDIOS_DIR/orbit-research/missions/write.yaml"
  run yq -r '.stages[0].name' "$mission"
  assert_output "decompose"

  run yq -r '.stages[1].name' "$mission"
  assert_output "write"

  run yq -r '.stages[1].orbits_to' "$mission"
  assert_output "decompose"
}

# ============================================================
# Sentinel-specific tests
# ============================================================

@test "sentinel: monitor mission has cron sensor" {
  local mission="$STUDIOS_DIR/orbit-sentinel/missions/monitor.yaml"
  run yq -r '.sensors.schedule.cron' "$mission"
  assert_output '0 6 * * *'
}

@test "sentinel: monitor mission has manual brief-gate" {
  local mission="$STUDIOS_DIR/orbit-sentinel/missions/monitor.yaml"
  run yq -r '.stages[] | select(.name == "brief-gate") | .type' "$mission"
  assert_output "manual"

  run yq -r '.stages[] | select(.name == "brief-gate") | .default' "$mission"
  assert_output "approve"

  run yq -r '.stages[] | select(.name == "brief-gate") | .timeout' "$mission"
  assert_output "12h"
}

@test "sentinel: watchlist.yaml exists with sources" {
  local watchlist="$STUDIOS_DIR/orbit-sentinel/watchlist.yaml"
  [ -f "$watchlist" ]
  run yq -r '.sources | length' "$watchlist"
  [ "$output" -gt 0 ]
}

@test "sentinel: monitor mission has assemble stage before brief-gate" {
  local mission="$STUDIOS_DIR/orbit-sentinel/missions/monitor.yaml"
  run yq -r '.stages[] | select(.name == "assemble") | .component' "$mission"
  assert_output "brief-writer"

  run yq -r '.stages[] | select(.name == "brief-gate") | .depends_on[0]' "$mission"
  assert_output "assemble"
}

@test "sentinel: brief-writer delivers daily-brief.md" {
  local comp="$STUDIOS_DIR/orbit-sentinel/components/brief-writer/brief-writer.yaml"
  run yq -r '.delivers[0]' "$comp"
  assert_output "intelligence/daily-brief.md"
}

@test "sentinel: analyst has preflight scripts" {
  local comp="$STUDIOS_DIR/orbit-sentinel/components/analyst/analyst.yaml"
  run yq -r '.preflight[0]' "$comp"
  assert_output "scripts/fetch-source.sh"

  run yq -r '.preflight[1]' "$comp"
  assert_output "scripts/distil-content.sh"
}

# ============================================================
# Fieldops-specific tests
# ============================================================

@test "fieldops: remediator has restricted policy" {
  local comp="$STUDIOS_DIR/orbit-fieldops/components/remediator/remediator.yaml"
  run yq -r '.tools.policy' "$comp"
  assert_output "restricted"
}

@test "fieldops: remediator has assigned tools" {
  local comp="$STUDIOS_DIR/orbit-fieldops/components/remediator/remediator.yaml"
  local tools
  tools=$(yq -r '.tools.assigned[]' "$comp" | sort)
  echo "$tools" | grep -q "apply-config-patch"
  echo "$tools" | grep -q "check-health"
  echo "$tools" | grep -q "notify-operator"
  echo "$tools" | grep -q "restart-service"
}

@test "fieldops: respond mission has file sensor with cascade block" {
  local mission="$STUDIOS_DIR/orbit-fieldops/missions/respond.yaml"
  run yq -r '.sensors.paths[0]' "$mission"
  assert_output "logs/anomaly-trigger"

  run yq -r '.sensors.cascade' "$mission"
  assert_output "block"
}

@test "fieldops: respond mission has flight rule cost ceiling" {
  local mission="$STUDIOS_DIR/orbit-fieldops/missions/respond.yaml"
  run yq -r '.flight_rules[0].name' "$mission"
  assert_output "cost-ceiling"

  run yq -r '.flight_rules[0].on_violation' "$mission"
  assert_output "abort"
}

@test "fieldops: orbit.yaml.edge variant exists with opencode" {
  local variant="$STUDIOS_DIR/orbit-fieldops/orbit.yaml.edge"
  [ -f "$variant" ]
  run yq -r '.defaults.agent' "$variant"
  assert_output "opencode"

  run yq -r '.defaults.model' "$variant"
  assert_output "ollama/qwen2.5-coder"
}

@test "fieldops: RISK-REGISTRY.md exists" {
  [ -f "$STUDIOS_DIR/orbit-fieldops/RISK-REGISTRY.md" ]
  grep -q 'restricted' "$STUDIOS_DIR/orbit-fieldops/RISK-REGISTRY.md"
}

@test "fieldops: tool scripts exist and are executable" {
  for tool in read-logs check-health restart-service apply-config-patch notify-operator _auth-check; do
    local tool_path="$STUDIOS_DIR/orbit-fieldops/tools/${tool}.sh"
    [ -f "$tool_path" ] || { echo "Missing: $tool_path" >&2; return 1; }
    [ -x "$tool_path" ] || { echo "Not executable: $tool_path" >&2; return 1; }
  done
}

@test "fieldops: tools/INDEX.md exists" {
  [ -f "$STUDIOS_DIR/orbit-fieldops/tools/INDEX.md" ]
}

@test "fieldops: diagnostician has preflight" {
  local comp="$STUDIOS_DIR/orbit-fieldops/components/diagnostician/diagnostician.yaml"
  run yq -r '.preflight[0]' "$comp"
  assert_output "scripts/extract-anomalies.sh"
}

# ============================================================
# All studios: scripts have proper shebangs
# ============================================================

@test "studios: all scripts have bash shebang and set -euo pipefail" {
  local failures=()
  while IFS= read -r script; do
    if ! head -1 "$script" | grep -q '#!/usr/bin/env bash'; then
      failures+=("$(basename "$(dirname "$(dirname "$script")")")/$(basename "$script") missing shebang")
    fi
    if ! head -10 "$script" | grep -q 'set -euo pipefail'; then
      failures+=("$(basename "$(dirname "$(dirname "$script")")")/$(basename "$script") missing set -euo pipefail")
    fi
  done < <(find "$STUDIOS_DIR" -name '*.sh' -type f)

  if [ ${#failures[@]} -gt 0 ]; then
    printf '%s\n' "${failures[@]}" >&2
    return 1
  fi
}

# ============================================================
# Studio count verification
# ============================================================

@test "studios: exactly 3 studios exist" {
  local count
  count=$(find "$STUDIOS_DIR" -maxdepth 1 -type d -name 'orbit-*' | wc -l | tr -d ' ')
  [ "$count" -eq 3 ]
}

# ============================================================
# Fixture validation
# ============================================================

@test "research: fixture JSON files are valid" {
  local fixtures_dir="$STUDIOS_DIR/orbit-research/fixtures"
  for f in tasks.json atomic-tasks.json write-tasks.json; do
    jq '.' "$fixtures_dir/$f" >/dev/null 2>&1 || { echo "Invalid JSON: $f" >&2; return 1; }
  done
}

@test "research: fixture files exist" {
  local fixtures_dir="$STUDIOS_DIR/orbit-research/fixtures"
  [ -f "$fixtures_dir/brief.md" ]
  [ -f "$fixtures_dir/tasks.json" ]
  [ -f "$fixtures_dir/atomic-tasks.json" ]
  [ -f "$fixtures_dir/write-tasks.json" ]
  [ -f "$fixtures_dir/finding.md" ]
}

@test "sentinel: fixture JSON files are valid" {
  local fixtures_dir="$STUDIOS_DIR/orbit-sentinel/fixtures"
  jq '.' "$fixtures_dir/tasks.json" >/dev/null 2>&1 || { echo "Invalid JSON: tasks.json" >&2; return 1; }
}

@test "sentinel: fixture files exist" {
  local fixtures_dir="$STUDIOS_DIR/orbit-sentinel/fixtures"
  [ -f "$fixtures_dir/watchlist.yaml" ]
  [ -f "$fixtures_dir/tasks.json" ]
  [ -f "$fixtures_dir/distilled-source.md" ]
  [ -f "$fixtures_dir/finding.md" ]
  [ -f "$fixtures_dir/daily-brief.md" ]
}

@test "fieldops: fixture JSON files are valid" {
  local fixtures_dir="$STUDIOS_DIR/orbit-fieldops/fixtures"
  for f in anomaly-report.json tasks.json; do
    jq '.' "$fixtures_dir/$f" >/dev/null 2>&1 || { echo "Invalid JSON: $f" >&2; return 1; }
  done
}

@test "fieldops: fixture files exist" {
  local fixtures_dir="$STUDIOS_DIR/orbit-fieldops/fixtures"
  [ -f "$fixtures_dir/anomaly-trigger" ]
  [ -f "$fixtures_dir/anomaly-report.json" ]
  [ -f "$fixtures_dir/tasks.json" ]
  [ -f "$fixtures_dir/app.log" ]
}
