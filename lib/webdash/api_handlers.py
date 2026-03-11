"""API endpoint handlers for Orbit Rover web dashboard."""

import json
import hashlib
import time
import os
import subprocess


def handle_graph(builder, yq_path, cache_dir, project_dir):
    """Handle /api/graph — full topology."""
    _maybe_refresh_cache(yq_path, cache_dir, project_dir)
    return 200, builder.build()


def handle_missions(builder, path_parts):
    """Handle /api/missions and /api/missions/{name}."""
    if len(path_parts) > 2:
        name = '/'.join(path_parts[2:])
        detail = builder.build_mission_detail(name)
        if detail is None:
            return 404, {'error': 'mission not found'}
        return 200, detail
    return 200, builder.build_missions()


def handle_components(builder, path_parts):
    """Handle /api/components and /api/components/{name}."""
    if len(path_parts) > 2:
        name = '/'.join(path_parts[2:])
        detail = builder.build_component_detail(name)
        if detail is None:
            return 404, {'error': 'component not found'}
        return 200, detail
    return 200, builder.build_components()


def handle_runs(builder, path_parts, query_params):
    """Handle /api/runs and /api/runs/{id}."""
    if len(path_parts) > 2:
        run_id = '/'.join(path_parts[2:])
        detail = builder.build_run_detail(run_id)
        if detail is None:
            return 404, {'error': 'run not found'}
        return 200, detail
    mission_filter = query_params.get('mission', [''])[0]
    return 200, builder.build_runs(mission_filter)


def handle_sensors(builder):
    """Handle /api/sensors."""
    return 200, builder.build_sensors()


def handle_flight_rules(builder):
    """Handle /api/flight-rules."""
    return 200, builder.build_flight_rules()


def handle_telemetry(builder):
    """Handle /api/telemetry."""
    return 200, builder.build_telemetry()


def handle_costs(builder):
    """Handle /api/costs."""
    return 200, builder.build_costs()


def handle_modules(builder):
    """Handle /api/modules."""
    return 200, builder.build_modules()




class SSEHandler:
    """Server-Sent Events handler with hash-based dedup."""

    def __init__(self, builder, yq_path, cache_dir, project_dir):
        self.builder = builder
        self.yq_path = yq_path
        self.cache_dir = cache_dir
        self.project_dir = project_dir
        self.last_hash = None

    def generate(self, wfile):
        """Generate SSE events. Yields graph data on changes, heartbeats otherwise."""
        try:
            while True:
                _maybe_refresh_cache(self.yq_path, self.cache_dir, self.project_dir)
                data = self.builder.build()
                data_json = json.dumps(data, separators=(',', ':'))
                data_hash = hashlib.md5(data_json.encode()).hexdigest()

                if data_hash != self.last_hash:
                    self.last_hash = data_hash
                    wfile.write(('data: %s\n\n' % data_json).encode())
                    wfile.flush()
                else:
                    # Heartbeat
                    wfile.write(': heartbeat\n\n'.encode())
                    wfile.flush()

                time.sleep(2)
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass


# ------------------------------------------------------------------
# YAML cache refresh
# ------------------------------------------------------------------

_yaml_mtimes = {}


def _maybe_refresh_cache(yq_path, cache_dir, project_dir):
    """Re-convert YAML to JSON if source files changed."""
    if not yq_path:
        return

    changed = False
    for subdir in ('missions', 'components', 'modules'):
        src_dir = os.path.join(project_dir, subdir)
        if not os.path.isdir(src_dir):
            continue
        dst_dir = os.path.join(cache_dir, subdir)

        for fname in os.listdir(src_dir):
            if not (fname.endswith('.yaml') or fname.endswith('.yml')):
                continue
            src_path = os.path.join(src_dir, fname)
            try:
                mtime = os.path.getmtime(src_path)
            except OSError:
                continue

            key = src_path
            if key in _yaml_mtimes and _yaml_mtimes[key] == mtime:
                continue

            # Convert
            base = fname.rsplit('.', 1)[0] + '.json'
            dst_path = os.path.join(dst_dir, base)
            os.makedirs(dst_dir, exist_ok=True)
            try:
                result = subprocess.run(
                    [yq_path, '-o=json', src_path],
                    capture_output=True, text=True, timeout=5
                )
                if result.returncode == 0:
                    with open(dst_path, 'w') as f:
                        f.write(result.stdout)
                    _yaml_mtimes[key] = mtime
                    changed = True
            except (subprocess.TimeoutExpired, OSError):
                pass

    return changed
