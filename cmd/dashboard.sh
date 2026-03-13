#!/usr/bin/env bash
set -euo pipefail

# dashboard.sh — orbit dashboard subcommand
# Live-updating TUI dashboard using gum (charmbracelet) for styling.
# Falls back to plain text when gum is not available.

# --------------------------------------------------------------------------
# State variables (populated by _dash_load_state)
# --------------------------------------------------------------------------
declare -a _DASH_COMPONENTS=()
declare -a _DASH_COMP_STATUS=()
declare -a _DASH_COMP_DESC=()
declare -a _DASH_MISSIONS=()
declare -a _DASH_MISSION_STATUS=()
_DASH_SENSOR_COUNT=0
_DASH_GATE_COUNT=0
_DASH_REQUEST_COUNT=0
_DASH_LAST_RUN="none"
_DASH_CASCADE_COUNT=0

# Per-mission run state (parallel arrays indexed by mission)
declare -A _DASH_RUN_STATUS=()
declare -A _DASH_RUN_STAGES=()

# --------------------------------------------------------------------------
# Gum detection
# --------------------------------------------------------------------------
_dash_has_gum() {
  command -v gum >/dev/null 2>&1
}

# --------------------------------------------------------------------------
# Terminal width
# --------------------------------------------------------------------------
_dash_term_width() {
  tput cols 2>/dev/null || echo 80
}

_dash_is_wide() {
  [[ $(_dash_term_width) -ge 60 ]]
}

# --------------------------------------------------------------------------
# Status icons
# --------------------------------------------------------------------------
_dash_icon() {
  case "$1" in
    success|completed)  echo "✓" ;;
    running|active)     echo "●" ;;
    pending)            echo "○" ;;
    failed)             echo "✗" ;;
    blocked)            echo "⊘" ;;
    paused)             echo "⏸" ;;
    retrying)           echo "↻" ;;
    waiting)            echo "⏳" ;;
    *)                  echo "·" ;;
  esac
}

# --------------------------------------------------------------------------
# Load state from .orbit/ — registry, runs, sensors, gates, requests
# --------------------------------------------------------------------------
# Reads all dashboard-relevant state from disk into parallel arrays and
# counters. Called at the start of each render cycle so the TUI reflects
# the latest state. Sources: registry.json (components/missions), runs/
# (mission execution state), sensors/*.pid, manual/ (pending gates),
# tool-requests/pending.jsonl, cascade/active.json.
_dash_load_state() {
  local state_dir="${ORBIT_STATE_DIR:-.orbit}"

  # Reset arrays
  _DASH_COMPONENTS=()
  _DASH_COMP_STATUS=()
  _DASH_COMP_DESC=()
  _DASH_MISSIONS=()
  _DASH_MISSION_STATUS=()
  _DASH_RUN_STATUS=()
  _DASH_RUN_STAGES=()
  _DASH_SENSOR_COUNT=0
  _DASH_GATE_COUNT=0
  _DASH_REQUEST_COUNT=0
  _DASH_LAST_RUN="none"
  _DASH_CASCADE_COUNT=0

  # Load registry
  local registry="${state_dir}/registry.json"
  if [[ -f "$registry" ]]; then
    local comp_names
    comp_names=$(jq -r '.components | keys[]' "$registry" 2>/dev/null) || true
    while IFS= read -r name; do
      [[ -z "$name" ]] && continue
      _DASH_COMPONENTS+=("$name")
      local status desc
      status=$(jq -r --arg n "$name" '.components[$n].status // "unknown"' "$registry")
      desc=$(jq -r --arg n "$name" '.components[$n].description // ""' "$registry")
      _DASH_COMP_STATUS+=("$status")
      _DASH_COMP_DESC+=("$desc")
    done <<< "$comp_names"

    local mission_names
    mission_names=$(jq -r '.missions | keys[]' "$registry" 2>/dev/null) || true
    while IFS= read -r name; do
      [[ -z "$name" ]] && continue
      _DASH_MISSIONS+=("$name")
      local status
      status=$(jq -r --arg n "$name" '.missions[$n].status // "unknown"' "$registry")
      _DASH_MISSION_STATUS+=("$status")
    done <<< "$mission_names"
  fi

  # Load run state
  if [[ -d "${state_dir}/runs" ]]; then
    local latest_run
    latest_run=$(ls -1t "${state_dir}/runs/" 2>/dev/null | head -1) || true
    [[ -n "$latest_run" ]] && _DASH_LAST_RUN="$latest_run"

    for rdir in "${state_dir}/runs"/*/; do
      [[ -d "$rdir" ]] || continue
      if [[ -f "${rdir}mission.json" ]]; then
        local mission run_status
        mission=$(jq -r '.mission // ""' "${rdir}mission.json" 2>/dev/null) || true
        run_status=$(jq -r '.status // "unknown"' "${rdir}mission.json" 2>/dev/null) || true
        [[ -n "$mission" ]] && _DASH_RUN_STATUS["$mission"]="$run_status"

        # Count stage files
        if [[ -d "${rdir}stages" ]]; then
          local stage_info=""
          for sf in "${rdir}stages"/*.json; do
            [[ -f "$sf" ]] || continue
            local sname sstatus
            sname=$(jq -r '.name // "?"' "$sf" 2>/dev/null) || sname="?"
            sstatus=$(jq -r '.status // "unknown"' "$sf" 2>/dev/null) || sstatus="unknown"
            stage_info+="${sname}:${sstatus},"
          done
          [[ -n "$mission" ]] && _DASH_RUN_STAGES["$mission"]="${stage_info%,}"
        fi
      fi
    done
  fi

  # Count sensors
  if [[ -d "${state_dir}/sensors" ]]; then
    _DASH_SENSOR_COUNT=$(ls -1 "${state_dir}/sensors/"*.pid 2>/dev/null | wc -l | tr -d ' ') || _DASH_SENSOR_COUNT=0
  fi

  # Count pending gates
  if [[ -d "${state_dir}/manual" ]]; then
    for gate_dir in "${state_dir}/manual"/*/; do
      [[ -d "$gate_dir" ]] || continue
      if [[ -f "${gate_dir}prompt.json" ]] && [[ ! -f "${gate_dir}response.json" ]]; then
        _DASH_GATE_COUNT=$((_DASH_GATE_COUNT + 1))
      fi
    done
  fi

  # Count pending tool requests
  local pending_file="${state_dir}/tool-requests/pending.jsonl"
  if [[ -f "$pending_file" ]]; then
    _DASH_REQUEST_COUNT=$(jq -c 'select(.status == "pending")' "$pending_file" 2>/dev/null | wc -l | tr -d ' ') || _DASH_REQUEST_COUNT=0
  fi

  # Count cascade entries
  local cascade_file="${state_dir}/cascade/active.json"
  if [[ -f "$cascade_file" ]]; then
    _DASH_CASCADE_COUNT=$(jq 'length' "$cascade_file" 2>/dev/null) || _DASH_CASCADE_COUNT=0
  fi
}

# --------------------------------------------------------------------------
# Render helpers — gum vs plain text branching
# --------------------------------------------------------------------------
# When gum (charmbracelet) is available and terminal is wide enough (≥60 cols),
# panels use gum style with borders and ANSI colors. Otherwise, plain text
# with simple headers and indentation. The banner uses per-character gradient
# coloring in gum mode, with three width-adaptive variants (full/compact/mini).
_dash_gum_style() {
  # Wrapper for gum style with consistent padding
  gum style --padding "0 1" "$@"
}

# Banner gradient colors matching Station's purple→cyan palette
# 256-color indices: purple through cyan
_DASH_GRADIENT=(63 62 61 33 39 45 51 87 123 159 195)
_DASH_STAR_COLOR=245

# Apply 256-color ANSI foreground to a string
_dash_fg() {
  printf '\033[38;5;%sm%s\033[0m' "$1" "$2"
}

# Colorize a single banner line with per-character styling
# Stars/decorations get dim color, block chars get gradient, orbit symbol gets cyan
_dash_color_line() {
  local line="$1"
  local color_idx="$2"
  local main_color="${_DASH_GRADIENT[$color_idx]}"
  local result=""
  local i char

  for (( i=0; i<${#line}; i++ )); do
    char="${line:$i:1}"
    case "$char" in
      [·˚✦.*])
        result+=$(_dash_fg "$_DASH_STAR_COLOR" "$char")
        ;;
      ◯)
        result+="\033[1m$(_dash_fg 51 "$char")\033[0m"
        ;;
      [█╗╝╚╔║═╬╣╠╩╦])
        result+="\033[1m$(_dash_fg "$main_color" "$char")\033[0m"
        ;;
      *)
        result+=$(_dash_fg "$main_color" "$char")
        ;;
    esac
  done

  printf '%b' "$result"
}

_dash_banner() {
  local width
  width=$(_dash_term_width)
  local ts
  ts=$(date +"%d %b %H:%M")

  # Select banner variant based on width
  local -a banner_lines=()

  if [[ $width -ge 74 ]]; then
    # Full banner — ORBIT block letters + thin ROVER beside it
    banner_lines=(
      '                                                                    '
      '        ·  ✦  ˚           . · .           ˚  ✦  ·                  '
      '     ✦              ·      ◯      ·              ✦                 '
      '   ██████╗ ██████╗ ██████╗ ██╗████████╗                            '
      '  ██╔═══██╗██╔══██╗██╔══██╗██║╚══██╔══╝  ┬─┐ ┌─┐ ┬  ┬┌─┐ ┬─┐    '
      '  ██║   ██║██████╔╝██████╔╝██║   ██║     ├┬┘ │ │ └┐┌┘├┤  ├┬┘ ✦  '
      '  ██║   ██║██╔══██╗██╔══██╗██║   ██║     ┴└─ └─┘  └┘ └─┘ ┴└─    '
      '  ╚██████╔╝██║  ██║██████╔╝██║   ██║                              '
      '   ╚═════╝ ╚═╝  ╚═╝╚═════╝ ╚═╝   ╚═╝                     ˚      '
      '        ·    ✦         ˚           ·    ✦     ·                    '
    )
  elif [[ $width -ge 48 ]]; then
    # Compact banner
    banner_lines=(
      '      ✦  ·    . · .    ·  ✦              '
      '  ╭──────────────────────────╮           '
      '  │   ◯ R B I T             │           '
      '  │       R O V E R         │    ✦      '
      '  ╰──────────────────────────╯           '
    )
  else
    # Mini banner
    banner_lines=(
      '◯ ORBIT ROVER'
    )
  fi

  if _dash_has_gum; then
    # Colorize per-character with gradient
    local total=${#banner_lines[@]}
    local gradient_len=${#_DASH_GRADIENT[@]}
    local colored_output=""

    for i in "${!banner_lines[@]}"; do
      local color_idx=$(( i * gradient_len / total ))
      [[ $color_idx -ge $gradient_len ]] && color_idx=$((gradient_len - 1))
      local colored_line
      colored_line=$(_dash_color_line "${banner_lines[$i]}" "$color_idx")
      colored_output+="${colored_line}"
      [[ $i -lt $((total - 1)) ]] && colored_output+=$'\n'
    done

    local inner_width=$((width - 4))
    [[ $inner_width -gt 80 ]] && inner_width=80
    [[ $inner_width -lt 20 ]] && inner_width=20

    local ts_pad=$(( inner_width - ${#ts} - 6 ))
    [[ $ts_pad -lt 1 ]] && ts_pad=1
    local ts_line
    ts_line=$(printf '%*s%s' "$ts_pad" '' "$ts")
    ts_line=$(_dash_fg 244 "$ts_line")

    printf '%b\n%b' "$colored_output" "$ts_line" | gum style \
      --width "$inner_width" \
      --border rounded \
      --border-foreground 99 \
      --padding "0 1"
  else
    # Plain text — no ANSI colors
    printf '%s\n' "${banner_lines[@]}"
    echo "  $ts"
    echo ""
  fi
}

_dash_missions_panel() {
  local lines=()

  if [[ ${#_DASH_MISSIONS[@]} -eq 0 ]]; then
    lines+=("  (no missions registered)")
  else
    for i in "${!_DASH_MISSIONS[@]}"; do
      local name="${_DASH_MISSIONS[$i]}"
      local reg_status="${_DASH_MISSION_STATUS[$i]}"

      # Use run status if available, otherwise registry status
      local display_status="${_DASH_RUN_STATUS[$name]:-$reg_status}"
      local icon
      icon=$(_dash_icon "$display_status")

      local line="  ${icon}  ${name}"
      # Right-align status
      local pad=$(( 44 - ${#line} - ${#display_status} ))
      [[ $pad -lt 1 ]] && pad=1
      local spacing
      spacing=$(printf '%*s' "$pad" '')
      lines+=("${line}${spacing}${display_status}")

      # Show stages if we have run data
      local stages="${_DASH_RUN_STAGES[$name]:-}"
      if [[ -n "$stages" ]]; then
        IFS=',' read -ra stage_arr <<< "$stages"
        local total=${#stage_arr[@]}
        local done_count=0
        for s in "${stage_arr[@]}"; do
          local sstatus="${s#*:}"
          [[ "$sstatus" == "completed" || "$sstatus" == "success" ]] && done_count=$((done_count + 1))
        done

        # Show each stage with tree connectors
        for j in "${!stage_arr[@]}"; do
          local s="${stage_arr[$j]}"
          local sname="${s%%:*}"
          local sstatus="${s#*:}"
          local sicon
          sicon=$(_dash_icon "$sstatus")
          local connector="├──"
          [[ $j -eq $((total - 1)) ]] && connector="└──"

          local progress_text="[${done_count}/${total}]"
          local bar=""
          if [[ $total -gt 0 ]]; then
            local pct=$(( done_count * 100 / total ))
            local filled=$(( pct / 10 ))
            local empty=$(( 10 - filled ))
            bar=$(printf '█%.0s' $(seq 1 "$filled" 2>/dev/null) || true)
            bar+=$(printf '░%.0s' $(seq 1 "$empty" 2>/dev/null) || true)
            bar+=" ${pct}%"
          fi

          lines+=("  ${connector} ${sicon} ${sname}  ${progress_text} ${bar}")
        done
      fi
    done
  fi

  if _dash_has_gum && _dash_is_wide; then
    local inner_width=$(( $(_dash_term_width) - 4 ))
    [[ $inner_width -gt 80 ]] && inner_width=80
    local header
    header=$(gum style --bold --foreground 212 "─ Missions")
    local content
    content=$(printf '%s\n' "${lines[@]}")
    local body
    body=$(printf '%s\n%s' "$header" "$content")
    echo "$body" | gum style \
      --width "$inner_width" \
      --border rounded \
      --border-foreground 212
  else
    echo "  Missions"
    echo "  --------"
    printf '%s\n' "${lines[@]}"
    echo ""
  fi
}

_dash_components_panel() {
  local lines=()

  if [[ ${#_DASH_COMPONENTS[@]} -eq 0 ]]; then
    lines+=("  (no components registered)")
  else
    for i in "${!_DASH_COMPONENTS[@]}"; do
      local name="${_DASH_COMPONENTS[$i]}"
      local status="${_DASH_COMP_STATUS[$i]}"
      local desc="${_DASH_COMP_DESC[$i]}"
      local icon
      icon=$(_dash_icon "$status")

      local info="${desc:+$desc}"
      [[ -z "$info" ]] && info="$status"

      local line="  ${icon}  ${name}"
      local pad=$(( 44 - ${#line} - ${#info} ))
      [[ $pad -lt 1 ]] && pad=1
      local spacing
      spacing=$(printf '%*s' "$pad" '')
      lines+=("${line}${spacing}${info}")
    done
  fi

  if _dash_has_gum && _dash_is_wide; then
    local inner_width=$(( $(_dash_term_width) - 4 ))
    [[ $inner_width -gt 80 ]] && inner_width=80
    local header
    header=$(gum style --bold --foreground 81 "─ Components")
    local content
    content=$(printf '%s\n' "${lines[@]}")
    local body
    body=$(printf '%s\n%s' "$header" "$content")
    echo "$body" | gum style \
      --width "$inner_width" \
      --border rounded \
      --border-foreground 81
  else
    echo "  Components"
    echo "  ----------"
    printf '%s\n' "${lines[@]}"
    echo ""
  fi
}

_dash_metrics_bar() {
  local sensors="Sensors: ${_DASH_SENSOR_COUNT} active"
  local gates="Gates: ${_DASH_GATE_COUNT} pending"
  local requests="Requests: ${_DASH_REQUEST_COUNT} pending"
  local cascade=""
  [[ $_DASH_CASCADE_COUNT -gt 0 ]] && cascade="Cascade: ${_DASH_CASCADE_COUNT}"

  local parts="${sensors}  │  ${gates}  │  ${requests}"
  [[ -n "$cascade" ]] && parts+="  │  ${cascade}"

  if _dash_has_gum && _dash_is_wide; then
    local inner_width=$(( $(_dash_term_width) - 4 ))
    [[ $inner_width -gt 80 ]] && inner_width=80
    gum style \
      --width "$inner_width" \
      --border rounded \
      --border-foreground 244 \
      --foreground 244 \
      "  ${parts}  "
  else
    echo "  ${parts}"
    echo ""
  fi
}

_dash_footer() {
  local hint="  r refresh  q quit"
  if _dash_has_gum; then
    gum style --foreground 244 --faint "$hint"
  else
    echo "$hint"
  fi
}

# --------------------------------------------------------------------------
# Full render
# --------------------------------------------------------------------------
_dash_render() {
  _dash_load_state

  if _dash_has_gum && _dash_is_wide; then
    local banner missions components metrics footer
    banner=$(_dash_banner)
    missions=$(_dash_missions_panel)
    components=$(_dash_components_panel)
    metrics=$(_dash_metrics_bar)
    footer=$(_dash_footer)

    gum join --vertical \
      "$banner" \
      "$missions" \
      "$components" \
      "$metrics" \
      "$footer"
  else
    _dash_banner
    _dash_missions_panel
    _dash_components_panel
    _dash_metrics_bar
    _dash_footer
  fi
}

# --------------------------------------------------------------------------
# Main loop — refresh cycle with keyboard input
# --------------------------------------------------------------------------
# Clears screen, renders all panels, then blocks on read with a timeout
# equal to the refresh interval. 'q' exits, 'r' forces immediate refresh,
# any other key or timeout triggers the next cycle.
_dash_loop() {
  local refresh="$1"

  trap 'printf "\033[?25h"; exit 0' INT TERM

  printf '\033[?25l'

  while true; do
    printf '\033[2J\033[H'

    _dash_render

    local key=""
    read -rsn1 -t "$refresh" key 2>/dev/null || true
    case "$key" in
      q|Q) printf '\033[?25h'; exit 0 ;;
      r|R) continue ;;
    esac
  done
}

# --------------------------------------------------------------------------
# Entry point
# --------------------------------------------------------------------------
cmd_dashboard() {
  local refresh=2
  local once=false
  local no_color=false
  local web_mode=false
  local port=8067
  local no_open=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --refresh)
        refresh="$2"; shift 2
        ;;
      --once)
        once=true; shift
        ;;
      --no-color)
        no_color=true; shift
        ;;
      --web)
        web_mode=true; shift
        ;;
      --port)
        port="$2"; shift 2
        ;;
      --no-open)
        no_open=true; shift
        ;;
      --help|-h)
        cat <<'EOF'
Usage: orbit dashboard [options]

Live-updating TUI dashboard for Orbit Rover.

Options:
  --refresh N    Refresh interval in seconds (default: 2)
  --once         Render once and exit (no loop)
  --no-color     Disable colors and borders
  --web          Launch web dashboard instead of TUI
  --port N       Web dashboard port (default: 8067, only with --web)
  --no-open      Don't auto-open browser (only with --web)
  --help         Show this help
EOF
        return 0
        ;;
      *)
        echo "Unknown option: $1" >&2
        return 1
        ;;
    esac
  done

  if [[ "$web_mode" == "true" ]]; then
    _dashboard_web "$port" "$no_open"
    return
  fi

  if [[ "$no_color" == "true" ]]; then
    # Force plain text mode by hiding gum
    _dash_has_gum() { return 1; }
  fi

  if [[ "$once" == "true" ]]; then
    _dash_render
  else
    _dash_loop "$refresh"
  fi
}

# --------------------------------------------------------------------------
# Web dashboard
# --------------------------------------------------------------------------
_dashboard_web() {
  local port="$1"
  local no_open="$2"
  local state_dir="${ORBIT_STATE_DIR:-.orbit}"
  local project_dir
  project_dir="$(pwd)"

  # Verify python3 available
  if ! command -v python3 >/dev/null 2>&1; then
    echo "[ROVER ERROR] python3 is required for the web dashboard" >&2
    return 1
  fi

  # Verify yq available
  local yq_path=""
  if command -v yq >/dev/null 2>&1; then
    yq_path="$(command -v yq)"
  else
    echo "[ROVER WARN] yq not found — config changes won't auto-refresh" >&2
  fi

  # Determine ORBIT_ROOT (where lib/webdash lives)
  local orbit_root="${ORBIT_ROOT:-}"
  if [[ -z "$orbit_root" ]]; then
    # Derive from this script's location
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    orbit_root="$(cd "$script_dir/.." && pwd)"
  fi

  local webdash_dir="$orbit_root/lib/webdash"
  if [[ ! -f "$webdash_dir/server.py" ]]; then
    echo "[ROVER ERROR] Web dashboard not found at $webdash_dir/server.py" >&2
    return 1
  fi

  # Create cache directory for YAML→JSON conversion
  local cache_dir="$state_dir/webdash-cache"
  mkdir -p "$cache_dir"

  # Pre-convert YAML configs to JSON
  _webdash_cache_configs "$cache_dir" "$yq_path"

  # Build registry if it doesn't exist
  if [[ ! -f "$state_dir/registry.json" ]]; then
    if type registry_build >/dev/null 2>&1; then
      registry_build "." 2>/dev/null || true
    fi
  fi

  local python_pid=""

  # Cleanup on exit
  _webdash_cleanup() {
    if [[ -n "$python_pid" ]] && kill -0 "$python_pid" 2>/dev/null; then
      kill "$python_pid" 2>/dev/null || true
      wait "$python_pid" 2>/dev/null || true
    fi
  }
  trap _webdash_cleanup INT TERM EXIT

  # Launch Python server
  python3 "$webdash_dir/server.py" \
    --port "$port" \
    --state-dir "$state_dir" \
    --project-dir "$project_dir" \
    --cache-dir "$cache_dir" \
    ${yq_path:+--yq-path "$yq_path"} &
  python_pid=$!

  # Brief pause for server startup
  sleep 0.5 2>/dev/null || sleep 1

  # Check server started
  if ! kill -0 "$python_pid" 2>/dev/null; then
    echo "[ROVER ERROR] Web dashboard failed to start" >&2
    return 1
  fi

  echo "Orbit Rover dashboard: http://localhost:${port}"
  echo "Press Ctrl+C to stop"

  # Auto-open browser unless --no-open
  if [[ "$no_open" != "true" ]]; then
    if command -v open >/dev/null 2>&1; then
      open "http://localhost:${port}" 2>/dev/null || true
    elif command -v xdg-open >/dev/null 2>&1; then
      xdg-open "http://localhost:${port}" 2>/dev/null || true
    fi
  fi

  # Wait for Python process
  wait "$python_pid" 2>/dev/null || true
}

_webdash_cache_configs() {
  local cache_dir="$1"
  local yq_path="$2"

  [[ -z "$yq_path" ]] && return 0

  mkdir -p "$cache_dir/missions" "$cache_dir/components" "$cache_dir/modules"

  local f base
  for f in missions/*.yaml missions/*.yml; do
    [[ -f "$f" ]] || continue
    base=$(basename "$f" | sed 's/\.\(yaml\|yml\)$/.json/')
    "$yq_path" -o=json "$f" > "$cache_dir/missions/$base" 2>/dev/null || true
  done

  for f in components/*.yaml components/*.yml; do
    [[ -f "$f" ]] || continue
    base=$(basename "$f" | sed 's/\.\(yaml\|yml\)$/.json/')
    "$yq_path" -o=json "$f" > "$cache_dir/components/$base" 2>/dev/null || true
  done

  for f in modules/*.yaml modules/*.yml; do
    [[ -f "$f" ]] || continue
    base=$(basename "$f" | sed 's/\.\(yaml\|yml\)$/.json/')
    "$yq_path" -o=json "$f" > "$cache_dir/modules/$base" 2>/dev/null || true
  done
}
