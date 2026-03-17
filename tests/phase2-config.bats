#!/usr/bin/env bats

load helpers/bats-support/load
load helpers/bats-assert/load

FIXTURE_DIR="$BATS_TEST_DIRNAME/fixtures"
LIB_DIR="$(cd "$BATS_TEST_DIRNAME/../lib" && pwd)"

# ============================================================================
# yaml.sh tests
# ============================================================================

@test "yaml_get returns scalar value" {
  source "$LIB_DIR/yaml.sh"
  run yaml_get "$FIXTURE_DIR/orbit.yaml" "system"
  assert_success
  assert_output "orbit"
}

@test "yaml_get returns nested scalar" {
  source "$LIB_DIR/yaml.sh"
  run yaml_get "$FIXTURE_DIR/orbit.yaml" "defaults.agent"
  assert_success
  assert_output "claude-code"
}

@test "yaml_get returns empty for missing key" {
  source "$LIB_DIR/yaml.sh"
  run yaml_get "$FIXTURE_DIR/orbit.yaml" "nonexistent.key"
  assert_success
  assert_output ""
}

@test "yaml_get_array returns array elements" {
  source "$LIB_DIR/yaml.sh"
  run yaml_get_array "$FIXTURE_DIR/component-worker.yaml" "delivers"
  assert_success
  assert_line --index 0 "output/report.json"
  assert_line --index 1 "output/report.md"
}

@test "yaml_get_array returns empty for missing key" {
  source "$LIB_DIR/yaml.sh"
  run yaml_get_array "$FIXTURE_DIR/orbit.yaml" "nonexistent"
  assert_success
  assert_output ""
}

@test "yaml_get_map returns map keys" {
  source "$LIB_DIR/yaml.sh"
  run yaml_get_map "$FIXTURE_DIR/orbit.yaml" "defaults"
  assert_success
  assert_line "agent"
  assert_line "model"
  assert_line "timeout"
  assert_line "max_turns"
}

@test "yaml_exists returns 0 for existing key" {
  source "$LIB_DIR/yaml.sh"
  run yaml_exists "$FIXTURE_DIR/orbit.yaml" "system"
  assert_success
}

@test "yaml_exists returns 1 for missing key" {
  source "$LIB_DIR/yaml.sh"
  run yaml_exists "$FIXTURE_DIR/orbit.yaml" "nonexistent"
  assert_failure
}

# ============================================================================
# config_load_system tests
# ============================================================================

@test "config_load_system loads all fields" {
  source "$LIB_DIR/config.sh"
  config_load_system "$FIXTURE_DIR/orbit.yaml"

  [[ "${ORBIT_SYSTEM[system]}" == "orbit" ]]
  [[ "${ORBIT_SYSTEM[version]}" == "1" ]]
  [[ "${ORBIT_SYSTEM[defaults.agent]}" == "claude-code" ]]
  [[ "${ORBIT_SYSTEM[defaults.model]}" == "sonnet" ]]
  [[ "${ORBIT_SYSTEM[defaults.timeout]}" == "300" ]]
  [[ "${ORBIT_SYSTEM[defaults.max_turns]}" == "10" ]]
  [[ "${ORBIT_SYSTEM[settings.log_level]}" == "info" ]]
  [[ "${ORBIT_SYSTEM[settings.workspace]}" == "." ]]
  [[ "${ORBIT_SYSTEM[settings.state_dir]}" == ".orbit" ]]
  [[ "${ORBIT_SYSTEM[orbits.default_max]}" == "20" ]]
  [[ "${ORBIT_SYSTEM[orbits.deadlock_threshold]}" == "3" ]]
}

@test "config_load_system applies defaults for missing fields" {
  source "$LIB_DIR/config.sh"

  # Create a minimal orbit.yaml
  local tmp
  tmp=$(mktemp -d)
  cat > "$tmp/orbit.yaml" <<'EOF'
system: orbit
version: 1
EOF
  config_load_system "$tmp/orbit.yaml"

  [[ "${ORBIT_SYSTEM[defaults.agent]}" == "claude-code" ]]
  [[ "${ORBIT_SYSTEM[defaults.model]}" == "sonnet" ]]
  [[ "${ORBIT_SYSTEM[defaults.timeout]}" == "300" ]]
  [[ "${ORBIT_SYSTEM[defaults.max_turns]}" == "10" ]]
  [[ "${ORBIT_SYSTEM[settings.log_level]}" == "info" ]]
  [[ "${ORBIT_SYSTEM[orbits.default_max]}" == "20" ]]
  [[ "${ORBIT_SYSTEM[orbits.deadlock_threshold]}" == "3" ]]

  rm -rf "$tmp"
}

@test "config_load_system fails on missing file" {
  source "$LIB_DIR/config.sh"
  run config_load_system "/nonexistent/orbit.yaml"
  assert_failure
  assert_output --partial "System config not found"
}

# ============================================================================
# config_load_component tests
# ============================================================================

@test "config_load_component loads all fields" {
  source "$LIB_DIR/config.sh"
  # Load system first for defaults
  config_load_system "$FIXTURE_DIR/orbit.yaml"
  config_load_component "$FIXTURE_DIR/component-worker.yaml"

  [[ "${ORBIT_COMPONENT[component]}" == "worker" ]]
  [[ "${ORBIT_COMPONENT[status]}" == "active" ]]
  [[ "${ORBIT_COMPONENT[description]}" == "Executes atomic tasks one per orbit" ]]
  [[ "${ORBIT_COMPONENT[agent]}" == "claude-code" ]]
  [[ "${ORBIT_COMPONENT[model]}" == "opus" ]]
  [[ "${ORBIT_COMPONENT[prompt]}" == "prompts/worker.md" ]]
  [[ "${ORBIT_COMPONENT[timeout]}" == "600" ]]
  [[ "${ORBIT_COMPONENT[max_turns]}" == "15" ]]
}

@test "config_load_component loads sensor config" {
  source "$LIB_DIR/config.sh"
  config_load_system "$FIXTURE_DIR/orbit.yaml"
  config_load_component "$FIXTURE_DIR/component-worker.yaml"

  [[ "${ORBIT_COMPONENT[sensors.paths]}" == *"decisions/**/*.yaml"* ]]
  [[ "${ORBIT_COMPONENT[sensors.events]}" == *"create"* ]]
  [[ "${ORBIT_COMPONENT[sensors.cascade]}" == "block" ]]
  [[ "${ORBIT_COMPONENT[sensors.schedule.every]}" == "24h" ]]
  [[ "${ORBIT_COMPONENT[has_sensors]}" == "true" ]]
}

@test "config_load_component loads delivers" {
  source "$LIB_DIR/config.sh"
  config_load_system "$FIXTURE_DIR/orbit.yaml"
  config_load_component "$FIXTURE_DIR/component-worker.yaml"

  [[ "${ORBIT_COMPONENT[delivers]}" == *"output/report.json"* ]]
  [[ "${ORBIT_COMPONENT[delivers]}" == *"output/report.md"* ]]
}

@test "config_load_component loads tools config" {
  source "$LIB_DIR/config.sh"
  config_load_system "$FIXTURE_DIR/orbit.yaml"
  config_load_component "$FIXTURE_DIR/component-worker.yaml"

  [[ "${ORBIT_COMPONENT[tools.assigned]}" == *"read-file"* ]]
  [[ "${ORBIT_COMPONENT[tools.assigned]}" == *"write-file"* ]]
  [[ "${ORBIT_COMPONENT[tools.policy]}" == "restricted" ]]
}

@test "config_load_component loads orbits config" {
  source "$LIB_DIR/config.sh"
  config_load_system "$FIXTURE_DIR/orbit.yaml"
  config_load_component "$FIXTURE_DIR/component-worker.yaml"

  [[ "${ORBIT_COMPONENT[orbits.max]}" == "30" ]]
  [[ "${ORBIT_COMPONENT[orbits.success.when]}" == "file" ]]
  [[ "${ORBIT_COMPONENT[orbits.success.condition]}" == "output/done.flag" ]]
  [[ "${ORBIT_COMPONENT[orbits.deadlock.threshold]}" == "5" ]]
  [[ "${ORBIT_COMPONENT[orbits.deadlock.action]}" == "perspective" ]]
}

@test "config_load_component loads retry config" {
  source "$LIB_DIR/config.sh"
  config_load_system "$FIXTURE_DIR/orbit.yaml"
  config_load_component "$FIXTURE_DIR/component-worker.yaml"

  [[ "${ORBIT_COMPONENT[retry.max_attempts]}" == "2" ]]
  [[ "${ORBIT_COMPONENT[retry.backoff]}" == "exponential" ]]
  [[ "${ORBIT_COMPONENT[retry.initial_delay]}" == "5s" ]]
  [[ "${ORBIT_COMPONENT[retry.max_delay]}" == "60s" ]]
  [[ "${ORBIT_COMPONENT[retry.on_timeout]}" == "true" ]]
}

@test "config_load_component loads hooks" {
  source "$LIB_DIR/config.sh"
  config_load_system "$FIXTURE_DIR/orbit.yaml"
  config_load_component "$FIXTURE_DIR/component-worker.yaml"

  [[ "${ORBIT_COMPONENT[preflight]}" == *"distil-requirements"* ]]
  [[ "${ORBIT_COMPONENT[postflight]}" == *"log-result"* ]]
}

@test "config_load_component applies system defaults for missing fields" {
  source "$LIB_DIR/config.sh"
  config_load_system "$FIXTURE_DIR/orbit.yaml"
  config_load_component "$FIXTURE_DIR/component-minimal.yaml"

  # Should inherit system defaults
  [[ "${ORBIT_COMPONENT[agent]}" == "claude-code" ]]
  [[ "${ORBIT_COMPONENT[model]}" == "sonnet" ]]
  [[ "${ORBIT_COMPONENT[timeout]}" == "300" ]]
  [[ "${ORBIT_COMPONENT[max_turns]}" == "10" ]]
  [[ "${ORBIT_COMPONENT[status]}" == "active" ]]
  [[ "${ORBIT_COMPONENT[tools.policy]}" == "standard" ]]
  [[ "${ORBIT_COMPONENT[sensors.cascade]}" == "allow" ]]
}

@test "config_load_component fails on missing file" {
  source "$LIB_DIR/config.sh"
  run config_load_component "/nonexistent/component.yaml"
  assert_failure
  assert_output --partial "Component config not found"
}

# ============================================================================
# config_load_mission tests
# ============================================================================

@test "config_load_mission loads mission metadata" {
  source "$LIB_DIR/config.sh"
  config_load_mission "$FIXTURE_DIR/mission-implement.yaml"

  [[ "${ORBIT_MISSION[mission]}" == "implement" ]]
  [[ "${ORBIT_MISSION[status]}" == "active" ]]
  [[ "${ORBIT_MISSION[description]}" == "Implementation mission" ]]
}

@test "config_load_mission parses stages in order" {
  source "$LIB_DIR/config.sh"
  config_load_mission "$FIXTURE_DIR/mission-implement.yaml"

  [[ ${#ORBIT_MISSION_STAGES[@]} -eq 3 ]]

  # First stage: decompose
  local name0
  name0=$(echo "${ORBIT_MISSION_STAGES[0]}" | jq -r '.name')
  [[ "$name0" == "decompose" ]]

  # Second stage: work
  local name1
  name1=$(echo "${ORBIT_MISSION_STAGES[1]}" | jq -r '.name')
  [[ "$name1" == "work" ]]

  # Third stage: gate
  local name2
  name2=$(echo "${ORBIT_MISSION_STAGES[2]}" | jq -r '.name')
  [[ "$name2" == "gate" ]]
}

@test "config_load_mission parses depends_on" {
  source "$LIB_DIR/config.sh"
  config_load_mission "$FIXTURE_DIR/mission-implement.yaml"

  local deps
  deps=$(echo "${ORBIT_MISSION_STAGES[1]}" | jq -r '.depends_on[0]')
  [[ "$deps" == "decompose" ]]
}

@test "config_load_mission parses orbits_to and orbit_exit" {
  source "$LIB_DIR/config.sh"
  config_load_mission "$FIXTURE_DIR/mission-implement.yaml"

  local orbits_to max_orbits exit_when
  orbits_to=$(echo "${ORBIT_MISSION_STAGES[1]}" | jq -r '.orbits_to')
  max_orbits=$(echo "${ORBIT_MISSION_STAGES[1]}" | jq -r '.max_orbits')
  exit_when=$(echo "${ORBIT_MISSION_STAGES[1]}" | jq -r '.orbit_exit.when')

  [[ "$orbits_to" == "decompose" ]]
  [[ "$max_orbits" == "100" ]]
  [[ "$exit_when" == "bash" ]]
}

@test "config_load_mission parses waypoint" {
  source "$LIB_DIR/config.sh"
  config_load_mission "$FIXTURE_DIR/mission-implement.yaml"

  local waypoint
  waypoint=$(echo "${ORBIT_MISSION_STAGES[0]}" | jq -r '.waypoint')
  [[ "$waypoint" == "true" ]]
}

@test "config_load_mission parses manual gate stage" {
  source "$LIB_DIR/config.sh"
  config_load_mission "$FIXTURE_DIR/mission-implement.yaml"

  local type timeout default_opt
  type=$(echo "${ORBIT_MISSION_STAGES[2]}" | jq -r '.type')
  timeout=$(echo "${ORBIT_MISSION_STAGES[2]}" | jq -r '.timeout')
  default_opt=$(echo "${ORBIT_MISSION_STAGES[2]}" | jq -r '.default')

  [[ "$type" == "manual" ]]
  [[ "$timeout" == "72h" ]]
  [[ "$default_opt" == "reject" ]]
}

@test "config_load_mission parses flight rules" {
  source "$LIB_DIR/config.sh"
  config_load_mission "$FIXTURE_DIR/mission-implement.yaml"

  local rule_name violation
  rule_name=$(echo "${ORBIT_MISSION[flight_rules]}" | jq -r '.[0].name')
  violation=$(echo "${ORBIT_MISSION[flight_rules]}" | jq -r '.[0].on_violation')

  [[ "$rule_name" == "cost-ceiling" ]]
  [[ "$violation" == "abort" ]]
}

@test "config_load_mission fails on missing file" {
  source "$LIB_DIR/config.sh"
  run config_load_mission "/nonexistent/mission.yaml"
  assert_failure
  assert_output --partial "Mission config not found"
}

# ============================================================================
# config_load_module tests
# ============================================================================

@test "config_load_module loads module metadata" {
  source "$LIB_DIR/config.sh"
  config_load_module "$FIXTURE_DIR/module-risk-review.yaml"

  [[ "${ORBIT_MODULE[module]}" == "risk-review" ]]
  [[ "${ORBIT_MODULE[status]}" == "active" ]]
}

@test "config_load_module expands parameter placeholders in stages" {
  source "$LIB_DIR/config.sh"
  config_load_module "$FIXTURE_DIR/module-risk-review.yaml" "risk_id=RISK-008"

  local name0 name1
  name0=$(echo "${ORBIT_MODULE_STAGES[0]}" | jq -r '.name')
  name1=$(echo "${ORBIT_MODULE_STAGES[1]}" | jq -r '.name')

  [[ "$name0" == "validate-RISK-008" ]]
  [[ "$name1" == "analyse-RISK-008" ]]
}

@test "config_load_module expands parameter placeholders in delivers" {
  source "$LIB_DIR/config.sh"
  config_load_module "$FIXTURE_DIR/module-risk-review.yaml" "risk_id=RISK-008"

  [[ "${ORBIT_MODULE[delivers]}" == *"risk-RISK-008-report.md"* ]]
}

@test "config_load_module expands depends_on with parameters" {
  source "$LIB_DIR/config.sh"
  config_load_module "$FIXTURE_DIR/module-risk-review.yaml" "risk_id=RISK-008"

  local dep
  dep=$(echo "${ORBIT_MODULE_STAGES[1]}" | jq -r '.depends_on[0]')
  [[ "$dep" == "validate-RISK-008" ]]
}

# ============================================================================
# config_warn_unsupported tests
# ============================================================================

@test "config_warn_unsupported warns on webhooks" {
  source "$LIB_DIR/config.sh"
  run config_warn_unsupported "$FIXTURE_DIR/orbit-unsupported.yaml"
  assert_output --partial "'webhooks' not supported in Rover"
}

@test "config_warn_unsupported warns on streams" {
  source "$LIB_DIR/config.sh"
  run config_warn_unsupported "$FIXTURE_DIR/orbit-unsupported.yaml"
  assert_output --partial "'streams' not supported in Rover"
}

@test "config_warn_unsupported warns on serve" {
  source "$LIB_DIR/config.sh"
  run config_warn_unsupported "$FIXTURE_DIR/orbit-unsupported.yaml"
  assert_output --partial "'serve' not supported in Rover"
}

@test "config_warn_unsupported warns on state.backend: postgres" {
  source "$LIB_DIR/config.sh"
  run config_warn_unsupported "$FIXTURE_DIR/orbit-unsupported.yaml"
  assert_output --partial "'state.backend: postgres' not supported in Rover"
}

@test "config_warn_unsupported warns on resource_pool and inflight" {
  source "$LIB_DIR/config.sh"
  run config_warn_unsupported "$FIXTURE_DIR/component-unsupported.yaml"
  assert_output --partial "'resource_pool' not supported in Rover"
  assert_output --partial "'inflight' not supported in Rover"
}

@test "config_warn_unsupported does not warn on valid fields" {
  source "$LIB_DIR/config.sh"
  run config_warn_unsupported "$FIXTURE_DIR/orbit.yaml"
  assert_success
  refute_output --partial "ROVER WARN"
}

@test "config_warn_unsupported proceeds without error" {
  source "$LIB_DIR/config.sh"
  # Loading a config with unsupported fields should succeed
  config_load_system "$FIXTURE_DIR/orbit-unsupported.yaml"
  [[ "${ORBIT_SYSTEM[defaults.agent]}" == "claude-code" ]]
}

# ============================================================================
# registry_build tests
# ============================================================================

setup_registry() {
  export TEST_PROJECT_DIR
  TEST_PROJECT_DIR=$(mktemp -d)
  mkdir -p "$TEST_PROJECT_DIR/components"
  mkdir -p "$TEST_PROJECT_DIR/missions"
  mkdir -p "$TEST_PROJECT_DIR/.orbit"

  # Copy fixture files
  cp "$FIXTURE_DIR/component-worker.yaml" "$TEST_PROJECT_DIR/components/worker.yaml"
  cp "$FIXTURE_DIR/component-minimal.yaml" "$TEST_PROJECT_DIR/components/minimal-worker.yaml"
  cp "$FIXTURE_DIR/component-offline.yaml" "$TEST_PROJECT_DIR/components/offline-worker.yaml"
  cp "$FIXTURE_DIR/mission-implement.yaml" "$TEST_PROJECT_DIR/missions/implement.yaml"
  cp "$FIXTURE_DIR/mission-plan.yaml" "$TEST_PROJECT_DIR/missions/plan.yaml"
  cp "$FIXTURE_DIR/mission-offline.yaml" "$TEST_PROJECT_DIR/missions/offline-plan.yaml"
}

teardown_registry() {
  rm -rf "$TEST_PROJECT_DIR"
}

@test "registry_build creates registry.json" {
  setup_registry
  source "$LIB_DIR/registry.sh"
  registry_build "$TEST_PROJECT_DIR"

  [[ -f "$TEST_PROJECT_DIR/.orbit/registry.json" ]]
  teardown_registry
}

@test "registry_build includes all active components" {
  setup_registry
  source "$LIB_DIR/registry.sh"
  registry_build "$TEST_PROJECT_DIR"

  local count
  count=$(jq '.components | length' "$TEST_PROJECT_DIR/.orbit/registry.json")
  [[ "$count" -eq 2 ]]
  teardown_registry
}

@test "registry_build includes all missions" {
  setup_registry
  source "$LIB_DIR/registry.sh"
  registry_build "$TEST_PROJECT_DIR"

  local count
  count=$(jq '.missions | length' "$TEST_PROJECT_DIR/.orbit/registry.json")
  [[ "$count" -eq 2 ]]
  teardown_registry
}

@test "registry_build sets correct component fields" {
  setup_registry
  source "$LIB_DIR/registry.sh"
  registry_build "$TEST_PROJECT_DIR"

  local reg="$TEST_PROJECT_DIR/.orbit/registry.json"
  local status desc has_sensors
  status=$(jq -r '.components.worker.status' "$reg")
  desc=$(jq -r '.components.worker.description' "$reg")
  has_sensors=$(jq -r '.components.worker.has_sensors' "$reg")

  [[ "$status" == "active" ]]
  [[ "$desc" == "Executes atomic tasks one per orbit" ]]
  [[ "$has_sensors" == "true" ]]
  teardown_registry
}

@test "registry_build excludes offline components" {
  setup_registry
  source "$LIB_DIR/registry.sh"
  registry_build "$TEST_PROJECT_DIR"

  local key_exists
  key_exists=$(jq '.components | has("offline-worker")' "$TEST_PROJECT_DIR/.orbit/registry.json")
  [[ "$key_exists" == "false" ]]
  teardown_registry
}

@test "registry_build excludes offline missions" {
  setup_registry
  source "$LIB_DIR/registry.sh"
  registry_build "$TEST_PROJECT_DIR"

  local key_exists
  key_exists=$(jq '.missions | has("offline-plan")' "$TEST_PROJECT_DIR/.orbit/registry.json")
  [[ "$key_exists" == "false" ]]
  teardown_registry
}

@test "registry_build records delivers array" {
  setup_registry
  source "$LIB_DIR/registry.sh"
  registry_build "$TEST_PROJECT_DIR"

  local delivers_count
  delivers_count=$(jq '.components.worker.delivers | length' "$TEST_PROJECT_DIR/.orbit/registry.json")
  [[ "$delivers_count" -eq 2 ]]
  teardown_registry
}

@test "registry_build sets built_at timestamp" {
  setup_registry
  source "$LIB_DIR/registry.sh"
  registry_build "$TEST_PROJECT_DIR"

  local built_at
  built_at=$(jq -r '.built_at' "$TEST_PROJECT_DIR/.orbit/registry.json")
  [[ -n "$built_at" ]]
  [[ "$built_at" != "null" ]]
  teardown_registry
}

@test "registry_build includes mission file paths" {
  setup_registry
  source "$LIB_DIR/registry.sh"
  registry_build "$TEST_PROJECT_DIR"

  local file
  file=$(jq -r '.missions.implement.file' "$TEST_PROJECT_DIR/.orbit/registry.json")
  [[ "$file" == "missions/implement.yaml" ]]
  teardown_registry
}

# ============================================================================
# registry_load tests
# ============================================================================

@test "registry_load returns registry contents" {
  setup_registry
  source "$LIB_DIR/registry.sh"
  registry_build "$TEST_PROJECT_DIR"

  run registry_load "$TEST_PROJECT_DIR"
  assert_success

  local comp_count
  comp_count=$(echo "$output" | jq '.components | length')
  [[ "$comp_count" -eq 2 ]]
  teardown_registry
}

@test "registry_load fails when registry not built" {
  local tmp
  tmp=$(mktemp -d)
  source "$LIB_DIR/registry.sh"
  run registry_load "$tmp"
  assert_failure
  assert_output --partial "Registry not found"
  rm -rf "$tmp"
}

# ============================================================================
# registry_get_component tests
# ============================================================================

@test "registry_get_component returns file path" {
  setup_registry
  source "$LIB_DIR/registry.sh"
  registry_build "$TEST_PROJECT_DIR"

  run registry_get_component "worker" "$TEST_PROJECT_DIR"
  assert_success
  assert_output "components/worker.yaml"
  teardown_registry
}

@test "registry_get_component warns on unknown component" {
  setup_registry
  source "$LIB_DIR/registry.sh"
  registry_build "$TEST_PROJECT_DIR"

  run registry_get_component "nonexistent" "$TEST_PROJECT_DIR"
  assert_failure
  assert_output --partial "not found in registry"
  teardown_registry
}

# ============================================================================
# registry_validate_target tests
# ============================================================================

@test "registry_validate_target accepts known component" {
  setup_registry
  source "$LIB_DIR/registry.sh"
  registry_build "$TEST_PROJECT_DIR"

  run registry_validate_target "component:worker" "$TEST_PROJECT_DIR"
  assert_success
  teardown_registry
}

@test "registry_validate_target warns on unknown component" {
  setup_registry
  source "$LIB_DIR/registry.sh"
  registry_build "$TEST_PROJECT_DIR"

  run registry_validate_target "component:unknown-component" "$TEST_PROJECT_DIR"
  assert_failure
  assert_output --partial "insight target 'component:unknown-component' not found in registry"
  teardown_registry
}

@test "registry_validate_target accepts known mission" {
  setup_registry
  source "$LIB_DIR/registry.sh"
  registry_build "$TEST_PROJECT_DIR"

  run registry_validate_target "mission:implement" "$TEST_PROJECT_DIR"
  assert_success
  teardown_registry
}

@test "registry_validate_target accepts project scope without validation" {
  setup_registry
  source "$LIB_DIR/registry.sh"
  registry_build "$TEST_PROJECT_DIR"

  run registry_validate_target "project:myproject" "$TEST_PROJECT_DIR"
  assert_success
  teardown_registry
}

@test "registry_validate_target warns on unknown scope" {
  setup_registry
  source "$LIB_DIR/registry.sh"
  registry_build "$TEST_PROJECT_DIR"

  run registry_validate_target "invalid:something" "$TEST_PROJECT_DIR"
  assert_failure
  assert_output --partial "Unknown target scope"
  teardown_registry
}

# ============================================================================
# registry_build with unsupported fields
# ============================================================================

@test "registry_build collects unsupported field warnings" {
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/components" "$tmp/missions" "$tmp/.orbit"
  cp "$FIXTURE_DIR/component-unsupported.yaml" "$tmp/components/unsupported-worker.yaml"

  source "$LIB_DIR/registry.sh"
  registry_build "$tmp"

  local warn_count
  warn_count=$(jq '.warnings | length' "$tmp/.orbit/registry.json")
  [[ "$warn_count" -gt 0 ]]

  # Check that warnings mention the unsupported fields
  local warnings
  warnings=$(jq -r '.warnings[]' "$tmp/.orbit/registry.json")
  echo "$warnings" | grep -q "resource_pool"
  echo "$warnings" | grep -q "inflight"

  rm -rf "$tmp"
}
