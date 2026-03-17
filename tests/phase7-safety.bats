#!/usr/bin/env bats

load helpers/bats-support/load
load helpers/bats-assert/load

setup() {
  TEST_DIR="$(mktemp -d)"
  STATE_DIR="${TEST_DIR}/.orbit"
  mkdir -p "$STATE_DIR"

  ORBIT_LIB_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../lib" && pwd)"
  source "$ORBIT_LIB_DIR/util.sh"
  source "$ORBIT_LIB_DIR/manual_gate.sh"
  source "$ORBIT_LIB_DIR/flight_rules.sh"
  source "$ORBIT_LIB_DIR/waypoints.sh"
  source "$ORBIT_LIB_DIR/retry.sh"
  source "$ORBIT_LIB_DIR/stop.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Helper: write response.json directly to a run-scoped gate path (for background responders in tests)
_respond_to_gate() {
  local run_id="$1" gate_id="$2" option="$3"
  local gate_dir="${STATE_DIR}/runs/${run_id}/manual/${gate_id}"
  mkdir -p "$gate_dir"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  printf '{"gate_id":"%s","option":"%s","responded_at":"%s"}' "$gate_id" "$option" "$now" \
    > "${gate_dir}/response.json"
}

# ==========================================================================
# Manual Gate — prompt.json schema
# ==========================================================================

@test "manual_gate_open writes correct prompt.json" {
  # Create run directory so gate can be scoped to it
  mkdir -p "${STATE_DIR}/runs/run-001"

  # Respond immediately in background — write response directly to run-scoped path
  (sleep 0.2 && _respond_to_gate "run-001" "test-gate" "approve") &

  local result
  result=$(manual_gate_open "test-gate" "my-mission" "run-001" \
    "Please review" '["approve","reject"]' "1" "reject" "$STATE_DIR")

  assert_equal "$result" "approve"

  # Verify prompt.json was written with correct schema
  local pfile="${STATE_DIR}/runs/run-001/manual/test-gate/prompt.json"
  assert [ -f "$pfile" ]

  run jq -r '.gate_id' "$pfile"
  assert_output "test-gate"

  run jq -r '.mission' "$pfile"
  assert_output "my-mission"

  run jq -r '.run_id' "$pfile"
  assert_output "run-001"

  run jq -r '.prompt' "$pfile"
  assert_output "Please review"

  run jq -r '.options | length' "$pfile"
  assert_output "2"

  run jq -r '.default' "$pfile"
  assert_output "reject"

  run jq -r '.timeout_at' "$pfile"
  refute_output ""

  run jq -r '.created_at' "$pfile"
  refute_output ""
}

@test "manual_gate_open returns default on timeout" {
  mkdir -p "${STATE_DIR}/runs/run-002"

  # Use very short timeout (fractional hours = ~1 second)
  local result
  result=$(manual_gate_open "timeout-gate" "my-mission" "run-002" \
    "Review needed" '["approve","reject"]' "0.0003" "reject" "$STATE_DIR")

  assert_equal "$result" "reject"

  # Verify response.json was written with default
  local rfile="${STATE_DIR}/runs/run-002/manual/timeout-gate/response.json"
  assert [ -f "$rfile" ]
  run jq -r '.option' "$rfile"
  assert_output "reject"
}

# ==========================================================================
# Manual Gate — respond
# ==========================================================================

@test "manual_gate_respond writes response.json correctly" {
  # Create gate under a run directory
  mkdir -p "${STATE_DIR}/runs/run-resp/manual/resp-gate"
  echo '{"gate_id":"resp-gate"}' > "${STATE_DIR}/runs/run-resp/manual/resp-gate/prompt.json"

  manual_gate_respond "resp-gate" "iterate" "$STATE_DIR"

  local rfile="${STATE_DIR}/runs/run-resp/manual/resp-gate/response.json"
  assert [ -f "$rfile" ]

  run jq -r '.gate_id' "$rfile"
  assert_output "resp-gate"

  run jq -r '.option' "$rfile"
  assert_output "iterate"

  run jq -r '.responded_at' "$rfile"
  refute_output ""
}

@test "manual_gate_respond fails for nonexistent gate" {
  run manual_gate_respond "no-such-gate" "approve" "$STATE_DIR"
  assert_failure
}

# ==========================================================================
# Manual Gate — list pending
# ==========================================================================

@test "manual_gate_list_pending finds gates without responses" {
  # Create two gates under a run — one pending, one responded
  mkdir -p "${STATE_DIR}/runs/run-list/manual/pending-gate"
  echo '{"gate_id":"pending-gate","mission":"m1","run_id":"run-list","options":["approve","reject"],"timeout_at":"2099-01-01T00:00:00Z","created_at":"2026-01-01T00:00:00Z"}' \
    > "${STATE_DIR}/runs/run-list/manual/pending-gate/prompt.json"

  mkdir -p "${STATE_DIR}/runs/run-list/manual/done-gate"
  echo '{"gate_id":"done-gate","mission":"m1","run_id":"run-list","options":["approve"],"timeout_at":"2099-01-01T00:00:00Z","created_at":"2026-01-01T00:00:00Z"}' \
    > "${STATE_DIR}/runs/run-list/manual/done-gate/prompt.json"
  echo '{"option":"approve"}' > "${STATE_DIR}/runs/run-list/manual/done-gate/response.json"

  run manual_gate_list_pending "$STATE_DIR"
  assert_success
  assert_output --partial "pending-gate"
  refute_output --partial "done-gate"
}

@test "manual_gate_list_pending shows no pending when all responded" {
  mkdir -p "${STATE_DIR}/runs/run-done/manual/g1"
  echo '{"gate_id":"g1"}' > "${STATE_DIR}/runs/run-done/manual/g1/prompt.json"
  echo '{"option":"approve"}' > "${STATE_DIR}/runs/run-done/manual/g1/response.json"

  run manual_gate_list_pending "$STATE_DIR"
  assert_success
  assert_output "No pending gates."
}

# ==========================================================================
# Manual Gate — approve / reject convenience
# ==========================================================================

@test "manual_gate_approve writes correct option" {
  mkdir -p "${STATE_DIR}/runs/run-ap/manual/ap-gate"
  echo '{"gate_id":"ap-gate"}' > "${STATE_DIR}/runs/run-ap/manual/ap-gate/prompt.json"

  manual_gate_approve "ap-gate" "approve" "$STATE_DIR"

  run jq -r '.option' "${STATE_DIR}/runs/run-ap/manual/ap-gate/response.json"
  assert_output "approve"
}

@test "manual_gate_approve with custom option" {
  mkdir -p "${STATE_DIR}/runs/run-custom/manual/custom-gate"
  echo '{"gate_id":"custom-gate"}' > "${STATE_DIR}/runs/run-custom/manual/custom-gate/prompt.json"

  manual_gate_approve "custom-gate" "iterate" "$STATE_DIR"

  run jq -r '.option' "${STATE_DIR}/runs/run-custom/manual/custom-gate/response.json"
  assert_output "iterate"
}

@test "manual_gate_reject writes reject option" {
  mkdir -p "${STATE_DIR}/runs/run-rej/manual/rej-gate"
  echo '{"gate_id":"rej-gate"}' > "${STATE_DIR}/runs/run-rej/manual/rej-gate/prompt.json"

  manual_gate_reject "rej-gate" "$STATE_DIR"

  run jq -r '.option' "${STATE_DIR}/runs/run-rej/manual/rej-gate/response.json"
  assert_output "reject"
}

# ==========================================================================
# Manual Gate — run isolation
# ==========================================================================

@test "gate from prior run does not auto-approve new run" {
  # Run 1: open gate and respond
  mkdir -p "${STATE_DIR}/runs/run-A"
  (_respond_to_gate "run-A" "shared-gate" "approve") &
  local result_a
  result_a=$(manual_gate_open "shared-gate" "my-mission" "run-A" \
    "Review" '["approve","reject"]' "1" "reject" "$STATE_DIR")
  assert_equal "$result_a" "approve"

  # Run 2: same gate_id, different run — should NOT find run-A's response
  mkdir -p "${STATE_DIR}/runs/run-B"
  # Use a very short timeout so it falls through to default if not properly isolated
  local result_b
  result_b=$(manual_gate_open "shared-gate" "my-mission" "run-B" \
    "Review again" '["approve","reject"]' "0.0003" "reject" "$STATE_DIR")

  # Should get default "reject" (timeout), NOT "approve" from run-A
  assert_equal "$result_b" "reject"

  # Verify both runs have independent state
  assert [ -f "${STATE_DIR}/runs/run-A/manual/shared-gate/response.json" ]
  assert [ -f "${STATE_DIR}/runs/run-B/manual/shared-gate/response.json" ]

  run jq -r '.option' "${STATE_DIR}/runs/run-A/manual/shared-gate/response.json"
  assert_output "approve"
  run jq -r '.option' "${STATE_DIR}/runs/run-B/manual/shared-gate/response.json"
  assert_output "reject"
}

# ==========================================================================
# Flight Rules — warn continues
# ==========================================================================

@test "flight_rules_check warn continues execution" {
  local rules='[{"name":"token-warn","condition":"metrics.total_tokens < 100","on_violation":"warn","message":"Token warning"}]'
  local metrics='{"total_tokens":200,"cost_usd":0,"duration_seconds":0,"orbit_count":0}'

  run flight_rules_check "$rules" "$metrics"
  assert_success
}

@test "flight_rules_check abort returns 2" {
  local rules='[{"name":"token-hard","condition":"metrics.total_tokens < 100","on_violation":"abort","message":"Token limit exceeded"}]'
  local metrics='{"total_tokens":200,"cost_usd":0,"duration_seconds":0,"orbit_count":0}'

  run flight_rules_check "$rules" "$metrics"
  assert_failure
  assert_equal "$status" 2
}

@test "flight_rules_check passes when condition satisfied" {
  local rules='[{"name":"token-ok","condition":"metrics.total_tokens < 500","on_violation":"abort","message":"Token limit"}]'
  local metrics='{"total_tokens":100,"cost_usd":0,"duration_seconds":0,"orbit_count":0}'

  run flight_rules_check "$rules" "$metrics"
  assert_success
}

@test "flight_rules_check expands metrics.total_tokens" {
  local rules='[{"name":"t1","condition":"metrics.total_tokens < 1000","on_violation":"abort","message":"test"}]'
  local metrics='{"total_tokens":500,"cost_usd":0,"duration_seconds":0,"orbit_count":0}'

  run flight_rules_check "$rules" "$metrics"
  assert_success
}

@test "flight_rules_check expands metrics.duration_seconds" {
  local rules='[{"name":"time","condition":"metrics.duration_seconds < 3600","on_violation":"abort","message":"Time limit"}]'
  local metrics='{"total_tokens":0,"cost_usd":0,"duration_seconds":7200,"orbit_count":0}'

  run flight_rules_check "$rules" "$metrics"
  assert_failure
  assert_equal "$status" 2
}

@test "flight_rules_check multiple rules — warn then abort" {
  local rules='[
    {"name":"warn-rule","condition":"metrics.orbit_count < 5","on_violation":"warn","message":"Orbit warning"},
    {"name":"abort-rule","condition":"metrics.orbit_count < 3","on_violation":"abort","message":"Orbit abort"}
  ]'
  local metrics='{"total_tokens":0,"cost_usd":0,"duration_seconds":0,"orbit_count":10}'

  run flight_rules_check "$rules" "$metrics"
  assert_failure
  assert_equal "$status" 2
}

# ==========================================================================
# Metrics
# ==========================================================================

@test "metrics_update writes correct JSON" {
  local run_id="run-test-001"
  mkdir -p "${STATE_DIR}/runs/${run_id}"
  local start_epoch
  start_epoch=$(date -u +%s)

  metrics_update "$run_id" 5 "$start_epoch" "$STATE_DIR"

  local mfile="${STATE_DIR}/runs/${run_id}/metrics.json"
  assert [ -f "$mfile" ]

  run jq -r '.orbit_count' "$mfile"
  assert_output "5"

  run jq -r '.total_tokens' "$mfile"
  assert_output "0"

  # duration_seconds should be >= 0
  local dur
  dur=$(jq -r '.duration_seconds' "$mfile")
  assert [ "$dur" -ge 0 ]
}

@test "metrics_read returns metrics" {
  local run_id="run-test-002"
  mkdir -p "${STATE_DIR}/runs/${run_id}"
  echo '{"total_tokens":1000,"cost_usd":0.5,"duration_seconds":120,"orbit_count":3}' \
    > "${STATE_DIR}/runs/${run_id}/metrics.json"

  run metrics_read "$run_id" "$STATE_DIR"
  assert_success

  local tokens
  tokens=$(echo "$output" | jq -r '.total_tokens')
  assert_equal "$tokens" "1000"
}

@test "metrics_read returns defaults when no file" {
  run metrics_read "nonexistent" "$STATE_DIR"
  assert_success

  local orbit_count
  orbit_count=$(echo "$output" | jq -r '.orbit_count')
  assert_equal "$orbit_count" "0"
}

# ==========================================================================
# Waypoints
# ==========================================================================

@test "waypoint_save creates waypoint file" {
  local run_id="run-wp-001"
  mkdir -p "${STATE_DIR}/runs/${run_id}"

  waypoint_save "decompose" "my-mission" "$run_id" "$STATE_DIR"

  local wpfile="${STATE_DIR}/runs/${run_id}/waypoints/decompose.json"
  assert [ -f "$wpfile" ]

  run jq -r '.stage' "$wpfile"
  assert_output "decompose"

  run jq -r '.mission' "$wpfile"
  assert_output "my-mission"

  run jq -r '.status' "$wpfile"
  assert_output "completed"
}

@test "waypoint_get_last returns most recent waypoint" {
  local run_id="run-wp-002"
  mkdir -p "${STATE_DIR}/runs/${run_id}/waypoints"

  # Save two waypoints with different timestamps
  echo '{"stage":"stage-a","mission":"m","saved_at":"2026-01-01T00:00:00Z","status":"completed"}' \
    > "${STATE_DIR}/runs/${run_id}/waypoints/stage-a.json"
  echo '{"stage":"stage-b","mission":"m","saved_at":"2026-01-02T00:00:00Z","status":"completed"}' \
    > "${STATE_DIR}/runs/${run_id}/waypoints/stage-b.json"

  run waypoint_get_last "m" "$run_id" "$STATE_DIR"
  assert_output "stage-b"
}

@test "waypoint_get_last returns empty when no waypoints" {
  local run_id="run-wp-003"
  mkdir -p "${STATE_DIR}/runs/${run_id}"

  run waypoint_get_last "m" "$run_id" "$STATE_DIR"
  assert_output ""
}

@test "waypoint_resume_from returns last waypoint stage" {
  local run_id="run-wp-004"
  local run_dir="${STATE_DIR}/runs/${run_id}"
  mkdir -p "${run_dir}/waypoints"

  # Create mission.json
  echo '{"mission":"resume-test","started_at":"2026-01-01T00:00:00Z"}' \
    > "${run_dir}/mission.json"

  # Save waypoints
  echo '{"stage":"first","mission":"resume-test","saved_at":"2026-01-01T01:00:00Z","status":"completed"}' \
    > "${run_dir}/waypoints/first.json"
  echo '{"stage":"second","mission":"resume-test","saved_at":"2026-01-01T02:00:00Z","status":"completed"}' \
    > "${run_dir}/waypoints/second.json"

  run waypoint_resume_from "resume-test" "$STATE_DIR"
  assert_output "second"
}

@test "waypoint_resume_from returns empty when no runs" {
  run waypoint_resume_from "no-such-mission" "$STATE_DIR"
  assert_output ""
}

@test "waypoint_list shows all waypoints for a run" {
  local run_id="run-wp-005"
  mkdir -p "${STATE_DIR}/runs/${run_id}/waypoints"

  echo '{"stage":"s1","saved_at":"2026-01-01T00:00:00Z","status":"completed"}' \
    > "${STATE_DIR}/runs/${run_id}/waypoints/s1.json"
  echo '{"stage":"s2","saved_at":"2026-01-02T00:00:00Z","status":"completed"}' \
    > "${STATE_DIR}/runs/${run_id}/waypoints/s2.json"

  run waypoint_list "m" "$run_id" "$STATE_DIR"
  assert_success
  assert_output --partial "s1"
  assert_output --partial "s2"
}

# ==========================================================================
# Retry — should_retry
# ==========================================================================

@test "retry_should_retry respects max_attempts" {
  # attempt=2, max=2 → no retry
  run retry_should_retry 2 2 1 "false"
  assert_failure

  # attempt=1, max=2 → retry
  run retry_should_retry 1 2 1 "false"
  assert_success
}

@test "retry_should_retry does not retry on success" {
  run retry_should_retry 1 3 0 "false"
  assert_failure
}

@test "retry_should_retry retries on timeout when on_timeout is true" {
  # exit code 124 = timeout
  run retry_should_retry 1 3 124 "true"
  assert_success
}

@test "retry_should_retry does not retry on timeout when on_timeout is false" {
  run retry_should_retry 1 3 124 "false"
  assert_failure
}

@test "retry_should_retry retries on generic non-zero exit" {
  run retry_should_retry 1 3 1 "false"
  assert_success
}

# ==========================================================================
# Retry — delay calculation
# ==========================================================================

@test "retry_delay constant stays constant" {
  run retry_delay 1 "constant" 5 60
  assert_output "5"

  run retry_delay 3 "constant" 5 60
  assert_output "5"
}

@test "retry_delay exponential doubles" {
  run retry_delay 1 "exponential" 5 60
  assert_output "5"

  run retry_delay 2 "exponential" 5 60
  assert_output "10"

  run retry_delay 3 "exponential" 5 60
  assert_output "20"
}

@test "retry_delay exponential caps at max_delay" {
  run retry_delay 5 "exponential" 5 30
  # 5 * 2^4 = 80, capped at 30
  assert_output "30"
}

# ==========================================================================
# Retry — parse delay
# ==========================================================================

@test "_retry_parse_delay parses seconds" {
  run _retry_parse_delay "10s"
  assert_output "10"
}

@test "_retry_parse_delay parses minutes" {
  run _retry_parse_delay "2m"
  assert_output "120"
}

@test "_retry_parse_delay parses milliseconds" {
  run _retry_parse_delay "500ms"
  assert_output "1"
}

@test "_retry_parse_delay handles bare number" {
  run _retry_parse_delay "15"
  assert_output "15"
}

# ==========================================================================
# Retry — cleanup
# ==========================================================================

@test "retry_cleanup runs cleanup command" {
  local marker="${TEST_DIR}/cleanup-ran"
  retry_cleanup "touch $marker"
  assert [ -f "$marker" ]
}

@test "retry_cleanup does nothing with empty command" {
  run retry_cleanup ""
  assert_success
}

# ==========================================================================
# Stop — signal helpers
# ==========================================================================

@test "stop_request writes correct stop.json" {
  local run_id="run-stop-001"
  mkdir -p "${STATE_DIR}/runs/${run_id}"

  stop_request "$run_id" "$STATE_DIR"

  local sfile="${STATE_DIR}/runs/${run_id}/stop.json"
  assert [ -f "$sfile" ]

  run jq -r '.run_id' "$sfile"
  assert_output "run-stop-001"

  run jq -r '.requested_at' "$sfile"
  refute_output ""
}

@test "stop_is_requested returns 0 when file exists, 1 when not" {
  local run_id="run-stop-002"
  mkdir -p "${STATE_DIR}/runs/${run_id}"

  # No stop.json yet
  run stop_is_requested "$run_id" "$STATE_DIR"
  assert_failure

  # Write stop signal
  echo '{}' > "${STATE_DIR}/runs/${run_id}/stop.json"

  run stop_is_requested "$run_id" "$STATE_DIR"
  assert_success
}

@test "stop_find_running_run resolves mission name to run_id" {
  local run_id="run-stop-003"
  mkdir -p "${STATE_DIR}/runs/${run_id}"
  echo '{"mission":"my-mission","status":"running"}' \
    > "${STATE_DIR}/runs/${run_id}/mission.json"

  run stop_find_running_run "my-mission" "$STATE_DIR"
  assert_success
  assert_output "$run_id"
}

@test "stop_find_running_run returns 1 for non-running mission" {
  local run_id="run-stop-004"
  mkdir -p "${STATE_DIR}/runs/${run_id}"
  echo '{"mission":"done-mission","status":"complete"}' \
    > "${STATE_DIR}/runs/${run_id}/mission.json"

  run stop_find_running_run "done-mission" "$STATE_DIR"
  assert_failure
}

@test "stop_find_running_run returns 1 for unknown mission" {
  run stop_find_running_run "no-such-mission" "$STATE_DIR"
  assert_failure
}

@test "stop_clear removes the signal file" {
  local run_id="run-stop-005"
  mkdir -p "${STATE_DIR}/runs/${run_id}"
  echo '{}' > "${STATE_DIR}/runs/${run_id}/stop.json"

  assert [ -f "${STATE_DIR}/runs/${run_id}/stop.json" ]

  stop_clear "$run_id" "$STATE_DIR"

  assert [ ! -f "${STATE_DIR}/runs/${run_id}/stop.json" ]
}

@test "orbit loop exits with code 3 when stop signal present" {
  local run_id="run-stop-006"
  mkdir -p "${STATE_DIR}/runs/${run_id}"

  # Create stop signal before running
  stop_request "$run_id" "$STATE_DIR"

  # Create a minimal prompt file
  echo "test prompt" > "${TEST_DIR}/prompt.md"

  # Run orbit_run_component — it should exit 3 on first iteration
  source "$ORBIT_LIB_DIR/orbit_loop.sh"
  run orbit_run_component \
    --component "test-comp" \
    --prompt "${TEST_DIR}/prompt.md" \
    --success-when "file" \
    --success-condition "${TEST_DIR}/nonexistent" \
    --state-dir "$STATE_DIR" \
    --run-id "$run_id"

  assert_failure
  assert_equal "$status" 3
}

@test "cmd_stop errors on unknown mission" {
  export ORBIT_STATE_DIR="$STATE_DIR"
  source "$ORBIT_LIB_DIR/../cmd/stop.sh"

  run cmd_stop "nonexistent-mission"
  assert_failure
  assert_output --partial "No running mission"
}

@test "status shows stop-requested when stop.json exists" {
  local run_id="run-stop-007"
  local run_dir="${STATE_DIR}/runs/${run_id}"
  mkdir -p "${run_dir}/stages"

  echo '{"mission":"stop-test","status":"running","started_at":"2026-01-01T00:00:00Z"}' \
    > "${run_dir}/mission.json"
  echo '{}' > "${run_dir}/stop.json"

  export ORBIT_STATE_DIR="$STATE_DIR"
  source "$ORBIT_LIB_DIR/../cmd/status.sh"

  run _status_mission "stop-test" "$STATE_DIR"
  assert_success
  assert_output --partial "stop-requested"
}
