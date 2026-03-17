#!/usr/bin/env bats

load helpers/bats-support/load
load helpers/bats-assert/load

# Common setup
setup() {
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  TEST_TMP="$(mktemp -d)"

  source "$PROJECT_ROOT/lib/sensors/cascade.sh"
  source "$PROJECT_ROOT/lib/sensors/schedule.sh"
  source "$PROJECT_ROOT/lib/sensors/file_watch.sh"

  # Mock crontab: create a mock script that reads/writes a temp file
  MOCK_CRONTAB_FILE="$TEST_TMP/mock-crontab"
  touch "$MOCK_CRONTAB_FILE"
  export MOCK_CRONTAB_FILE

  mkdir -p "$TEST_TMP/bin"
  cp "$PROJECT_ROOT/tests/fixtures/mock-crontab" "$TEST_TMP/bin/crontab"
  chmod +x "$TEST_TMP/bin/crontab"
  export PATH="$TEST_TMP/bin:$PATH"
}

teardown() {
  # Clean up any background processes we started
  if [[ -d "$TEST_TMP/.orbit/sensors" ]]; then
    for pid_file in "$TEST_TMP"/.orbit/sensors/*.pid; do
      [[ -f "$pid_file" ]] || continue
      local pid
      pid=$(cat "$pid_file")
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    done
  fi
  rm -rf "$TEST_TMP"
}

# ============================================================
# Cascade lifecycle tests
# ============================================================

@test "cascade: mark_active creates active.json with component entry" {
  cascade_mark_active "worker" "run-abc123" "$TEST_TMP"

  [[ -f "$TEST_TMP/cascade/active.json" ]]
  run jq -r '.worker' "$TEST_TMP/cascade/active.json"
  assert_output "run-abc123"
}

@test "cascade: is_active returns 0 for active component" {
  cascade_mark_active "worker" "run-abc123" "$TEST_TMP"

  run cascade_is_active "worker" "$TEST_TMP"
  assert_success
}

@test "cascade: is_active returns 1 for inactive component" {
  cascade_mark_active "worker" "run-abc123" "$TEST_TMP"

  run cascade_is_active "decomposer" "$TEST_TMP"
  assert_failure
}

@test "cascade: mark_done removes component from active.json" {
  cascade_mark_active "worker" "run-abc123" "$TEST_TMP"
  cascade_mark_active "decomposer" "run-def456" "$TEST_TMP"
  cascade_mark_done "worker" "run-abc123" "$TEST_TMP"

  run cascade_is_active "worker" "$TEST_TMP"
  assert_failure

  # decomposer should still be there
  run cascade_is_active "decomposer" "$TEST_TMP"
  assert_success
}

@test "cascade: is_active returns 1 when no active.json exists" {
  run cascade_is_active "worker" "$TEST_TMP"
  assert_failure
}

@test "cascade: mark_active is idempotent — updates run_id" {
  cascade_mark_active "worker" "run-111" "$TEST_TMP"
  cascade_mark_active "worker" "run-222" "$TEST_TMP"

  run jq -r '.worker' "$TEST_TMP/cascade/active.json"
  assert_output "run-222"
}

@test "cascade: multiple components tracked simultaneously" {
  cascade_mark_active "worker" "run-111" "$TEST_TMP"
  cascade_mark_active "decomposer" "run-222" "$TEST_TMP"
  cascade_mark_active "reviewer" "run-333" "$TEST_TMP"

  run jq 'keys | length' "$TEST_TMP/cascade/active.json"
  assert_output "3"
}

@test "cascade: mark_done on missing file is no-op" {
  run cascade_mark_done "worker" "run-abc" "$TEST_TMP"
  assert_success
}

@test "cascade: handles malformed active.json gracefully" {
  mkdir -p "$TEST_TMP/cascade"
  echo "not json" > "$TEST_TMP/cascade/active.json"

  # mark_active should recover by defaulting to {}
  cascade_mark_active "worker" "run-abc" "$TEST_TMP"

  run jq -r '.worker' "$TEST_TMP/cascade/active.json"
  assert_output "run-abc"
}

# ============================================================
# Duration parsing tests
# ============================================================

@test "duration: parses hours" {
  run _parse_duration "24h"
  assert_output "86400"
}

@test "duration: parses minutes" {
  run _parse_duration "30m"
  assert_output "1800"
}

@test "duration: parses seconds" {
  run _parse_duration "45s"
  assert_output "45"
}

@test "duration: empty string returns 0" {
  run _parse_duration ""
  assert_output "0"
}

@test "duration: plain number treated as seconds" {
  run _parse_duration "60"
  assert_output "60"
}

@test "duration: 1h equals 3600" {
  run _parse_duration "1h"
  assert_output "3600"
}

# ============================================================
# Interval sensor tests
# ============================================================

@test "interval: creates PID file" {
  local state_dir="$TEST_TMP/.orbit"
  mkdir -p "$state_dir/sensors" "$state_dir/triggers"

  sensor_interval_start "test-comp" "1s" "$state_dir"

  [[ -f "$state_dir/sensors/test-comp-interval.pid" ]]
  local pid
  pid=$(cat "$state_dir/sensors/test-comp-interval.pid")
  [[ -n "$pid" ]]

  # Cleanup
  sensor_interval_stop "test-comp" "$state_dir"
}

@test "interval: writes trigger after interval elapses" {
  local state_dir="$TEST_TMP/.orbit"
  mkdir -p "$state_dir/sensors" "$state_dir/triggers"

  sensor_interval_start "test-comp" "1s" "$state_dir"

  # Wait for trigger to appear
  local tries=0
  while [[ ! -f "$state_dir/triggers/test-comp-schedule" ]] && [[ $tries -lt 5 ]]; do
    sleep 1
    tries=$((tries + 1))
  done

  [[ -f "$state_dir/triggers/test-comp-schedule" ]]

  sensor_interval_stop "test-comp" "$state_dir"
}

@test "interval: respects remaining time from last_run" {
  local state_dir="$TEST_TMP/.orbit"
  mkdir -p "$state_dir/sensors" "$state_dir/triggers" "$state_dir/state/test-comp"

  # Set last_run to 1 second ago with a 2s interval → should trigger in ~1s
  local now
  now=$(date +%s)
  echo $((now - 1)) > "$state_dir/state/test-comp/last_run"

  sensor_interval_start "test-comp" "2s" "$state_dir"

  # Should trigger faster than full 2s interval
  local tries=0
  while [[ ! -f "$state_dir/triggers/test-comp-schedule" ]] && [[ $tries -lt 5 ]]; do
    sleep 1
    tries=$((tries + 1))
  done

  [[ -f "$state_dir/triggers/test-comp-schedule" ]]
  # It should have triggered within 2 seconds (remaining ~1s)
  [[ $tries -le 2 ]]

  sensor_interval_stop "test-comp" "$state_dir"
}

@test "interval: stop kills process and removes PID file" {
  local state_dir="$TEST_TMP/.orbit"
  mkdir -p "$state_dir/sensors" "$state_dir/triggers"

  sensor_interval_start "test-comp" "60s" "$state_dir"

  local pid
  pid=$(cat "$state_dir/sensors/test-comp-interval.pid")

  sensor_interval_stop "test-comp" "$state_dir"

  [[ ! -f "$state_dir/sensors/test-comp-interval.pid" ]]
  # Process should be gone
  ! kill -0 "$pid" 2>/dev/null
}

# ============================================================
# Cron registration tests
# ============================================================

@test "cron: register adds entry with correct tag" {
  sensor_cron_register "my-worker" "0 9 * * 1" "/path/to/project" "$TEST_TMP"

  run crontab -l
  assert_output --partial "0 9 * * 1 /path/to/project/orbit trigger my-worker"
  assert_output --partial "# orbit-rover:my-worker"
}

@test "cron: register is idempotent — replaces not duplicates" {
  sensor_cron_register "my-worker" "0 9 * * 1" "/path/to/project" "$TEST_TMP"
  sensor_cron_register "my-worker" "0 10 * * 1" "/path/to/project" "$TEST_TMP"

  local count
  count=$(crontab -l | grep -c "orbit-rover:my-worker" || true)
  [[ "$count" -eq 1 ]]

  run crontab -l
  assert_output --partial "0 10 * * 1"
}

@test "cron: register multiple components" {
  sensor_cron_register "worker" "0 9 * * 1" "/project" "$TEST_TMP"
  sensor_cron_register "reviewer" "0 2 * * *" "/project" "$TEST_TMP"

  local count
  count=$(crontab -l | grep -c "orbit-rover:" || true)
  [[ "$count" -eq 2 ]]
}

@test "cron: unregister removes only tagged entry" {
  # Add a non-orbit entry first
  echo "30 * * * * /usr/bin/something" > "$MOCK_CRONTAB_FILE"

  sensor_cron_register "my-worker" "0 9 * * 1" "/project" "$TEST_TMP"
  sensor_cron_unregister "my-worker"

  run crontab -l
  assert_output --partial "/usr/bin/something"
  refute_output --partial "orbit-rover:my-worker"
}

@test "cron: unregister leaves other orbit entries intact" {
  sensor_cron_register "worker" "0 9 * * 1" "/project" "$TEST_TMP"
  sensor_cron_register "reviewer" "0 2 * * *" "/project" "$TEST_TMP"
  sensor_cron_unregister "worker"

  run crontab -l
  refute_output --partial "orbit-rover:worker"
  assert_output --partial "orbit-rover:reviewer"
}

@test "cron: unregister_all removes all orbit-rover entries" {
  echo "30 * * * * /usr/bin/something" > "$MOCK_CRONTAB_FILE"

  sensor_cron_register "worker" "0 9 * * 1" "/project" "$TEST_TMP"
  sensor_cron_register "reviewer" "0 2 * * *" "/project" "$TEST_TMP"
  sensor_cron_unregister_all

  run crontab -l
  assert_output --partial "/usr/bin/something"
  refute_output --partial "orbit-rover:"
}

@test "cron: unregister_all clears crontab when only orbit entries exist" {
  sensor_cron_register "worker" "0 9 * * 1" "/project" "$TEST_TMP"
  sensor_cron_unregister_all

  run crontab -l
  assert_output ""
}

@test "cron: list shows only orbit-rover entries" {
  echo "30 * * * * /usr/bin/something" > "$MOCK_CRONTAB_FILE"
  sensor_cron_register "worker" "0 9 * * 1" "/project" "$TEST_TMP"

  run sensor_cron_list
  assert_output --partial "orbit-rover:worker"
  refute_output --partial "/usr/bin/something"
}

@test "cron: list returns empty when no orbit entries" {
  echo "30 * * * * /usr/bin/something" > "$MOCK_CRONTAB_FILE"

  run sensor_cron_list
  assert_output ""
}

# ============================================================
# File watch tests
# ============================================================

@test "file_watch: creates PID file on start" {
  local state_dir="$TEST_TMP/.orbit"
  mkdir -p "$state_dir/sensors" "$state_dir/triggers" "$TEST_TMP/project/input"

  sensor_file_watch_start "test-comp" "input/*.txt" "" "1s" "allow" "$state_dir" "$TEST_TMP/project"

  [[ -f "$state_dir/sensors/test-comp-filewatch.pid" ]]

  sensor_file_watch_stop "test-comp" "$state_dir"
}

@test "file_watch: stop cleans up PID file" {
  local state_dir="$TEST_TMP/.orbit"
  mkdir -p "$state_dir/sensors" "$state_dir/triggers" "$TEST_TMP/project/input"

  sensor_file_watch_start "test-comp" "input/*.txt" "" "1s" "allow" "$state_dir" "$TEST_TMP/project"
  sensor_file_watch_stop "test-comp" "$state_dir"

  [[ ! -f "$state_dir/sensors/test-comp-filewatch.pid" ]]
}

@test "file_watch: polling detects new file" {
  local state_dir="$TEST_TMP/.orbit"
  local project_dir="$TEST_TMP/project"
  mkdir -p "$state_dir/sensors" "$state_dir/triggers" "$project_dir/input"

  # Create initial file so hash is non-empty
  echo "initial" > "$project_dir/input/test.txt"

  sensor_file_watch_start "test-comp" "input/*.txt" "" "1s" "allow" "$state_dir" "$project_dir"

  # Wait for watcher to initialize
  sleep 1

  # Modify file to trigger change
  echo "changed content" > "$project_dir/input/test.txt"

  # Wait for debounce (1s) + poll interval (1s) + margin
  local tries=0
  while [[ ! -f "$state_dir/triggers/test-comp-filewatch" ]] && [[ $tries -lt 6 ]]; do
    sleep 1
    tries=$((tries + 1))
  done

  [[ -f "$state_dir/triggers/test-comp-filewatch" ]]

  sensor_file_watch_stop "test-comp" "$state_dir"
}

@test "file_watch: cascade block prevents trigger when component active" {
  local state_dir="$TEST_TMP/.orbit"
  local project_dir="$TEST_TMP/project"
  mkdir -p "$state_dir/sensors" "$state_dir/triggers" "$project_dir/input"

  echo "initial" > "$project_dir/input/test.txt"

  # Mark component as active before starting watcher
  cascade_mark_active "test-comp" "run-block-test" "$state_dir"

  sensor_file_watch_start "test-comp" "input/*.txt" "" "1s" "block" "$state_dir" "$project_dir"

  sleep 1

  # Change file — should NOT trigger because cascade is block and component is active
  echo "changed" > "$project_dir/input/test.txt"

  # Wait longer than debounce
  sleep 4

  [[ ! -f "$state_dir/triggers/test-comp-filewatch" ]]

  sensor_file_watch_stop "test-comp" "$state_dir"
  cascade_mark_done "test-comp" "run-block-test" "$state_dir"
}

# ============================================================
# Hash watched paths tests
# ============================================================

@test "hash_watched_paths: returns empty for nonexistent paths" {
  run _hash_watched_paths "nonexistent/*.txt" "$TEST_TMP"
  assert_output ""
}

@test "hash_watched_paths: detects content changes" {
  mkdir -p "$TEST_TMP/data"
  echo "version 1" > "$TEST_TMP/data/file.txt"

  local hash1
  hash1=$(_hash_watched_paths "data/*.txt" "$TEST_TMP")

  echo "version 2" > "$TEST_TMP/data/file.txt"

  local hash2
  hash2=$(_hash_watched_paths "data/*.txt" "$TEST_TMP")

  [[ -n "$hash1" ]]
  [[ -n "$hash2" ]]
  [[ "$hash1" != "$hash2" ]]
}

@test "hash_watched_paths: consistent hash for same content" {
  mkdir -p "$TEST_TMP/data"
  echo "stable" > "$TEST_TMP/data/file.txt"

  local hash1
  hash1=$(_hash_watched_paths "data/*.txt" "$TEST_TMP")
  local hash2
  hash2=$(_hash_watched_paths "data/*.txt" "$TEST_TMP")

  assert_equal "$hash1" "$hash2"
}

# ============================================================
# Watch mode integration tests
# ============================================================

@test "watch: config loading parses sensor fields" {
  source "$PROJECT_ROOT/lib/config.sh"

  declare -gA ORBIT_SYSTEM=()
  ORBIT_SYSTEM[defaults.agent]="claude-code"
  ORBIT_SYSTEM[defaults.model]="sonnet"
  ORBIT_SYSTEM[defaults.timeout]="300"
  ORBIT_SYSTEM[defaults.max_turns]="10"

  config_load_component "$PROJECT_ROOT/tests/fixtures/component-sensor-test.yaml"

  assert_equal "${ORBIT_COMPONENT[sensors.paths]}" "input/**/*.txt,data/*.json"
  assert_equal "${ORBIT_COMPONENT[sensors.debounce]}" "2s"
  assert_equal "${ORBIT_COMPONENT[sensors.cascade]}" "block"
  assert_equal "${ORBIT_COMPONENT[sensors.schedule.every]}" "1s"
  assert_equal "${ORBIT_COMPONENT[has_sensors]}" "true"
}

@test "watch: component without sensors has has_sensors=false" {
  source "$PROJECT_ROOT/lib/config.sh"

  # Initialize ORBIT_SYSTEM to avoid unbound variable errors
  declare -gA ORBIT_SYSTEM=()
  ORBIT_SYSTEM[defaults.agent]="claude-code"
  ORBIT_SYSTEM[defaults.model]="sonnet"
  ORBIT_SYSTEM[defaults.timeout]="300"
  ORBIT_SYSTEM[defaults.max_turns]="10"

  config_load_component "$PROJECT_ROOT/tests/fixtures/component-minimal.yaml"

  assert_equal "${ORBIT_COMPONENT[has_sensors]}" "false"
}
