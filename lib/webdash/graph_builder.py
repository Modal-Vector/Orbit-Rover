"""Graph topology builder for Orbit Rover web dashboard.

Reads JSON config files (pre-converted from YAML by the bash entry point)
and .orbit/ runtime state to build the same graph topology as Go Station.
"""

import json
import os
import glob
import fnmatch
import time


class GraphBuilder:
    """Builds graph topology from config + runtime state."""

    def __init__(self, project_dir, state_dir, cache_dir):
        self.project_dir = project_dir
        self.state_dir = state_dir
        self.cache_dir = cache_dir

    # ------------------------------------------------------------------
    # Config loading (from JSON cache)
    # ------------------------------------------------------------------

    def _load_json(self, path):
        """Load a JSON file, return None on error."""
        try:
            with open(path, 'r') as f:
                return json.load(f)
        except (OSError, json.JSONDecodeError):
            return None

    def _list_configs(self, subdir):
        """List JSON config files in a cache subdirectory."""
        d = os.path.join(self.cache_dir, subdir)
        if not os.path.isdir(d):
            return {}
        result = {}
        for fname in sorted(os.listdir(d)):
            if fname.endswith('.json'):
                name = fname[:-5]  # strip .json
                data = self._load_json(os.path.join(d, fname))
                if data:
                    result[name] = data
            elif fname.endswith('.yaml') or fname.endswith('.yml'):
                # Shouldn't happen in cache, but handle gracefully
                continue
        return result

    def _load_mission_configs(self):
        return self._list_configs('missions')

    def _load_component_configs(self):
        return self._list_configs('components')

    def _load_module_configs(self):
        return self._list_configs('modules')

    # ------------------------------------------------------------------
    # Runtime state loading
    # ------------------------------------------------------------------

    def _load_registry(self):
        path = os.path.join(self.state_dir, 'registry.json')
        return self._load_json(path) or {}

    def _load_runs(self):
        """Load run state from .orbit/runs/*/mission.json."""
        runs_dir = os.path.join(self.state_dir, 'runs')
        if not os.path.isdir(runs_dir):
            return []
        runs = []
        for run_id in sorted(os.listdir(runs_dir), reverse=True):
            run_dir = os.path.join(runs_dir, run_id)
            mission_file = os.path.join(run_dir, 'mission.json')
            mission_data = self._load_json(mission_file)
            if not mission_data:
                continue
            mission_data['_run_id'] = run_id
            mission_data['_run_dir'] = run_dir
            # Load stage files
            stages_dir = os.path.join(run_dir, 'stages')
            stages = []
            if os.path.isdir(stages_dir):
                for sf in sorted(os.listdir(stages_dir)):
                    if sf.endswith('.json'):
                        stage_data = self._load_json(os.path.join(stages_dir, sf))
                        if stage_data:
                            stages.append(stage_data)
            mission_data['_stages'] = stages
            runs.append(mission_data)
        return runs

    def _load_sensor_pids(self):
        """Count active sensor PID files."""
        sensor_dir = os.path.join(self.state_dir, 'sensors')
        if not os.path.isdir(sensor_dir):
            return []
        pids = []
        for f in os.listdir(sensor_dir):
            if f.endswith('.pid'):
                pids.append(f[:-4])
        return pids

    def _load_telemetry(self):
        """Load telemetry JSONL entries."""
        tel_file = os.path.join(self.state_dir, 'telemetry.jsonl')
        if not os.path.isfile(tel_file):
            return []
        entries = []
        try:
            with open(tel_file, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line:
                        try:
                            entries.append(json.loads(line))
                        except json.JSONDecodeError:
                            continue
        except OSError:
            pass
        return entries

    # ------------------------------------------------------------------
    # Graph build (main topology)
    # ------------------------------------------------------------------

    def build(self):
        """Build the complete graph topology."""
        missions = self._load_mission_configs()
        components = self._load_component_configs()
        runs = self._load_runs()

        nodes = []
        edges = []
        edge_id = [0]

        def next_edge_id():
            edge_id[0] += 1
            return 'e%d' % edge_id[0]

        # Build status maps from active runs
        mission_status = {}
        stage_statuses = {}
        component_status = {}

        for run in runs:
            m_name = run.get('mission', '')
            m_status = run.get('status', '')
            if m_status in ('running', 'launched', 'executing'):
                mission_status[m_name] = run
                stage_map = {}
                for s in run.get('_stages', []):
                    stage_map[s.get('name', '')] = s
                stage_statuses[m_name] = stage_map

        # Component status from state.json
        state_file = os.path.join(self.state_dir, 'state.json')
        state_data = self._load_json(state_file) or {}
        for comp_entry in state_data.get('components', []):
            c_name = comp_entry.get('name', '')
            c_status = comp_entry.get('status', '')
            if c_status == 'running':
                component_status[c_name] = comp_entry

        # Count actives
        active_missions = len(mission_status)
        active_components = len(component_status)

        # Track placed components and instances
        placed_components = set()
        component_instances = {}  # comp_name -> [instance_node_ids]

        # Build mission + stage + component-instance nodes
        for m_name, mc in missions.items():
            mission_label = mc.get('mission', m_name)
            mission_id = 'mission:%s' % m_name

            status = 'defined'
            m_cfg_status = mc.get('status', '')
            if m_cfg_status == 'offline':
                status = 'offline'
            elif m_name in mission_status:
                status = mission_status[m_name].get('status', 'running')

            m_data = {}
            flight_rules = mc.get('flight_rules', [])
            if flight_rules:
                m_data['has_flight_rules'] = True
                m_data['flight_rule_count'] = len(flight_rules)

            nodes.append({
                'id': mission_id,
                'type': 'mission',
                'label': mission_label,
                'status': status,
                'data': m_data,
            })

            # Get runtime stage statuses for this mission
            m_stage_map = stage_statuses.get(m_name, {})

            for stage in mc.get('stages', []):
                # Module stage references — show as stage with module label
                module_ref = stage.get('module')
                if module_ref:
                    s_name = stage.get('name', module_ref)
                    stage_id = 'stage:%s:%s' % (m_name, s_name)
                    nodes.append({
                        'id': stage_id,
                        'type': 'stage',
                        'label': s_name,
                        'status': 'defined',
                        'parent': mission_id,
                        'data': {
                            'module': module_ref,
                            'params': stage.get('params', {}),
                            'stage_type': 'module',
                        },
                    })
                    for dep in stage.get('depends_on', []):
                        edges.append({
                            'id': next_edge_id(),
                            'source': 'stage:%s:%s' % (m_name, dep),
                            'target': stage_id,
                            'type': 'depends_on',
                        })
                    continue
                if stage.get('uses_module'):
                    continue

                s_name = stage.get('name', '')
                stage_id = 'stage:%s:%s' % (m_name, s_name)

                # Stage status
                s_status = 'defined'
                if m_name in mission_status:
                    s_status = 'pending'  # mission active, stages default pending
                if s_name in m_stage_map:
                    sv = m_stage_map[s_name]
                    s_status = sv.get('status', 'pending')

                s_data = {
                    'component': stage.get('component', ''),
                    'orbit': m_stage_map.get(s_name, {}).get('orbit', 0),
                    'max_orbits': stage.get('max_orbits', 0),
                }
                if stage.get('orbits_to'):
                    s_data['orbits_to'] = stage['orbits_to']
                if stage.get('waypoint'):
                    s_data['waypoint'] = True
                if stage.get('type'):
                    s_data['stage_type'] = stage['type']

                nodes.append({
                    'id': stage_id,
                    'type': 'stage',
                    'label': s_name,
                    'status': s_status,
                    'parent': mission_id,
                    'data': s_data,
                })

                # depends_on edges
                for dep in stage.get('depends_on', []):
                    edges.append({
                        'id': next_edge_id(),
                        'source': 'stage:%s:%s' % (m_name, dep),
                        'target': stage_id,
                        'type': 'depends_on',
                    })

                # orbits_to edges
                if stage.get('orbits_to'):
                    edges.append({
                        'id': next_edge_id(),
                        'source': stage_id,
                        'target': 'stage:%s:%s' % (m_name, stage['orbits_to']),
                        'type': 'orbits_to',
                    })

                # Component instance node inside stage
                comp_name = stage.get('component', '')
                if comp_name:
                    instance_id = 'component:%s:%s:%s' % (m_name, s_name, comp_name)
                    comp_cfg = components.get(comp_name, {})

                    c_status = 'defined'
                    c_orbit = 0
                    if comp_cfg.get('status') == 'offline':
                        c_status = 'offline'
                    elif comp_name in component_status:
                        c_status = component_status[comp_name].get('status', 'defined')
                        c_orbit = component_status[comp_name].get('orbit', 0)
                    elif m_name in mission_status:
                        # Derive from stage status
                        if s_name in m_stage_map:
                            ss = m_stage_map[s_name].get('status', '')
                            if ss in ('running', 'executing'):
                                c_status = ss

                    c_data = {'orbit': c_orbit}
                    if comp_cfg:
                        c_data['agent'] = comp_cfg.get('agent', '')
                        c_data['model'] = comp_cfg.get('model', '')
                        delivers = comp_cfg.get('delivers', [])
                        if delivers:
                            c_data['delivers'] = delivers
                            c_data['has_delivers'] = True
                        if comp_cfg.get('preflight'):
                            c_data['has_preflight'] = True
                        if comp_cfg.get('postflight'):
                            c_data['has_postflight'] = True
                        if comp_cfg.get('retry'):
                            c_data['has_retry'] = True
                        orbits = comp_cfg.get('orbits', {})
                        if isinstance(orbits, dict) and orbits.get('max'):
                            c_data['max_orbits'] = orbits['max']

                    label = comp_cfg.get('component', comp_name) if comp_cfg else comp_name

                    nodes.append({
                        'id': instance_id,
                        'type': 'component',
                        'label': label,
                        'status': c_status,
                        'parent': stage_id,
                        'data': c_data,
                    })

                    placed_components.add(comp_name)
                    component_instances.setdefault(comp_name, []).append(instance_id)

        # Standalone components (not in any stage)
        for c_name, comp_cfg in components.items():
            if c_name in placed_components:
                continue

            comp_id = 'component:%s' % c_name
            status = 'defined'
            orbit = 0
            if comp_cfg.get('status') == 'offline':
                status = 'offline'
            elif c_name in component_status:
                status = component_status[c_name].get('status', 'defined')
                orbit = component_status[c_name].get('orbit', 0)

            c_data = {
                'orbit': orbit,
                'agent': comp_cfg.get('agent', ''),
                'model': comp_cfg.get('model', ''),
            }
            delivers = comp_cfg.get('delivers', [])
            if delivers:
                c_data['delivers'] = delivers
                c_data['has_delivers'] = True
            if comp_cfg.get('preflight'):
                c_data['has_preflight'] = True
            if comp_cfg.get('postflight'):
                c_data['has_postflight'] = True
            if comp_cfg.get('retry'):
                c_data['has_retry'] = True
            orbits = comp_cfg.get('orbits', {})
            if isinstance(orbits, dict) and orbits.get('max'):
                c_data['max_orbits'] = orbits['max']

            nodes.append({
                'id': comp_id,
                'type': 'component',
                'label': comp_cfg.get('component', c_name),
                'status': status,
                'data': c_data,
            })

        # Sensor nodes — from component configs
        sensors_added = set()
        for c_name, comp_cfg in components.items():
            sensors = comp_cfg.get('sensors', {})
            if not sensors:
                continue
            paths = sensors.get('paths', [])
            if not paths:
                continue

            # Determine target type
            # Components with sensors can trigger themselves or missions
            target_type = 'component'
            target_name = c_name

            sensor_id = 'sensor:%s:%s' % (target_type, target_name)
            if sensor_id in sensors_added:
                continue
            sensors_added.add(sensor_id)

            nodes.append({
                'id': sensor_id,
                'type': 'sensor',
                'label': 'SENSORS',
                'status': '',
                'data': {
                    'patterns': paths,
                    'target': target_name,
                    'type': target_type,
                },
            })

            # Trigger edges
            if target_name in component_instances:
                for inst_id in component_instances[target_name]:
                    edges.append({
                        'id': next_edge_id(),
                        'source': sensor_id,
                        'target': inst_id,
                        'type': 'triggers',
                    })
            else:
                edges.append({
                    'id': next_edge_id(),
                    'source': sensor_id,
                    'target': 'component:%s' % target_name,
                    'type': 'triggers',
                })

        # Mission-level sensors (from mission config trigger field)
        for m_name, mc in missions.items():
            m_sensors = mc.get('sensors', {})
            if not m_sensors:
                # Check for trigger config
                trigger = mc.get('trigger', {})
                if not trigger:
                    continue
                paths = trigger.get('paths', [])
                if not paths:
                    continue
                m_sensors = {'paths': paths}

            paths = m_sensors.get('paths', [])
            if not paths:
                continue

            sensor_id = 'sensor:mission:%s' % m_name
            if sensor_id in sensors_added:
                continue
            sensors_added.add(sensor_id)

            nodes.append({
                'id': sensor_id,
                'type': 'sensor',
                'label': 'SENSORS',
                'status': '',
                'data': {
                    'patterns': paths,
                    'target': m_name,
                    'type': 'mission',
                },
            })

            edges.append({
                'id': next_edge_id(),
                'source': sensor_id,
                'target': 'mission:%s' % m_name,
                'type': 'triggers',
            })

        # Delivers edges
        self._build_delivers_edges(nodes, edges, edge_id, components)

        # Metrics
        tel_entries = self._load_telemetry()
        total_invocations = len(tel_entries)
        total_tokens = sum(e.get('tokens', 0) for e in tel_entries)
        total_cost = sum(e.get('cost', 0) for e in tel_entries)

        return {
            'nodes': nodes,
            'edges': edges,
            'metrics': {
                'total_invocations': total_invocations,
                'total_tokens': total_tokens,
                'total_cost': total_cost,
                'active_missions': active_missions,
                'active_components': active_components,
            },
            'updated_at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
        }

    def _build_delivers_edges(self, nodes, edges, edge_id, components):
        """Build delivers edges from component delivers patterns to stages."""
        # Collect deliverers
        deliverers = []
        for n in nodes:
            if n['type'] != 'component':
                continue
            delivers = n.get('data', {}).get('delivers', [])
            if delivers:
                deliverers.append((n['id'], delivers))

        if not deliverers:
            return

        # Collect sensor paths per component
        sensor_paths = {}
        for c_name, comp_cfg in components.items():
            sensors = comp_cfg.get('sensors', {})
            if sensors:
                sensor_paths[c_name] = sensors.get('paths', [])

        seen = set()
        for n in nodes:
            if n['type'] != 'stage':
                continue
            comp_name = n.get('data', {}).get('component', '')
            if not comp_name:
                continue
            paths = sensor_paths.get(comp_name, [])
            if not paths:
                continue

            for del_id, del_patterns in deliverers:
                for pattern in del_patterns:
                    for sensor_path in paths:
                        if fnmatch.fnmatch(os.path.basename(sensor_path),
                                           os.path.basename(pattern)):
                            dedup = '%s->%s' % (del_id, n['id'])
                            if dedup not in seen:
                                seen.add(dedup)
                                edge_id[0] += 1
                                edges.append({
                                    'id': 'e%d' % edge_id[0],
                                    'source': del_id,
                                    'target': n['id'],
                                    'type': 'delivers',
                                    'data': {'label': pattern},
                                })
                            break
                    else:
                        continue
                    break

    # ------------------------------------------------------------------
    # API data builders
    # ------------------------------------------------------------------

    def build_missions(self):
        """Return mission summaries."""
        missions = self._load_mission_configs()
        runs = self._load_runs()

        # Build run status map
        run_map = {}
        for run in runs:
            m_name = run.get('mission', '')
            if m_name not in run_map:
                run_map[m_name] = run

        result = []
        for m_name, mc in missions.items():
            ms = {
                'name': mc.get('mission', m_name),
                'description': mc.get('description', ''),
                'status': 'defined',
                'stages': [],
            }

            if m_name in run_map:
                r = run_map[m_name]
                ms['id'] = r.get('_run_id', '')
                ms['status'] = r.get('status', 'defined')
                ms['started_at'] = r.get('started_at', '')
                for s in r.get('_stages', []):
                    ms['stages'].append({
                        'name': s.get('name', ''),
                        'component': s.get('component', ''),
                        'status': s.get('status', 'pending'),
                        'orbit': s.get('orbit', 0),
                        'max_orbits': s.get('max_orbits', 0),
                        'orbits_to': s.get('orbits_to', ''),
                        'depends_on': s.get('depends_on', []),
                    })
            else:
                cfg_status = mc.get('status', '')
                if cfg_status:
                    ms['status'] = cfg_status
                for s in mc.get('stages', []):
                    if s.get('uses_module') or s.get('module'):
                        continue
                    ms['stages'].append(self._stage_summary_from_config(s))

            result.append(ms)
        return result

    def build_mission_detail(self, name):
        """Return detailed info for a specific mission."""
        missions = self._load_mission_configs()
        mc = missions.get(name)
        if not mc:
            return None

        runs = self._load_runs()
        run_data = None
        for r in runs:
            if r.get('mission') == name:
                run_data = r
                break

        ms = {
            'name': mc.get('mission', name),
            'description': mc.get('description', ''),
            'status': 'defined',
            'stages': [],
            'flight_rules': [],
        }

        if run_data:
            ms['id'] = run_data.get('_run_id', '')
            ms['status'] = run_data.get('status', 'defined')
            ms['started_at'] = run_data.get('started_at', '')
            for s in run_data.get('_stages', []):
                ms['stages'].append({
                    'name': s.get('name', ''),
                    'component': s.get('component', ''),
                    'status': s.get('status', 'pending'),
                    'orbit': s.get('orbit', 0),
                    'max_orbits': s.get('max_orbits', 0),
                    'orbits_to': s.get('orbits_to', ''),
                    'depends_on': s.get('depends_on', []),
                    'waypoint': s.get('waypoint', False),
                })
        else:
            cfg_status = mc.get('status', '')
            if cfg_status:
                ms['status'] = cfg_status
            for s in mc.get('stages', []):
                if s.get('uses_module') or s.get('module'):
                    continue
                ms['stages'].append(self._stage_summary_from_config(s))

        # Flight rules
        for fr in mc.get('flight_rules', []):
            ms['flight_rules'].append({
                'name': fr.get('name', ''),
                'condition': fr.get('condition', ''),
                'check_interval': fr.get('check_interval', ''),
                'on_violation': fr.get('on_violation', ''),
                'message': fr.get('message', ''),
            })

        return ms

    def build_components(self):
        """Return component summaries."""
        components = self._load_component_configs()
        state_data = self._load_json(os.path.join(self.state_dir, 'state.json')) or {}

        # Runtime status map
        comp_runtime = {}
        for c in state_data.get('components', []):
            comp_runtime[c.get('name', '')] = c

        result = []
        for c_name, comp_cfg in components.items():
            cs = {
                'name': comp_cfg.get('component', c_name),
                'description': comp_cfg.get('description', ''),
                'status': comp_cfg.get('status', 'defined') or 'defined',
                'agent': comp_cfg.get('agent', ''),
                'model': comp_cfg.get('model', ''),
                'orbit': 0,
                'sensors': [],
                'delivers': comp_cfg.get('delivers', []),
                'has_preflight': bool(comp_cfg.get('preflight')),
                'has_postflight': bool(comp_cfg.get('postflight')),
                'has_retry': bool(comp_cfg.get('retry')),
                'max_orbits': 0,
            }
            sensors = comp_cfg.get('sensors', {})
            if sensors:
                cs['sensors'] = sensors.get('paths', [])
            orbits = comp_cfg.get('orbits', {})
            if isinstance(orbits, dict) and orbits.get('max'):
                cs['max_orbits'] = orbits['max']

            # Overlay runtime
            if c_name in comp_runtime:
                rt = comp_runtime[c_name]
                cs['status'] = rt.get('status', cs['status'])
                cs['orbit'] = rt.get('orbit', 0)

            result.append(cs)

        result.sort(key=lambda x: x['name'])
        return result

    def build_component_detail(self, name):
        """Return detailed info for a specific component."""
        components = self._load_component_configs()
        comp_cfg = components.get(name)
        if not comp_cfg:
            return None

        cs = {
            'name': comp_cfg.get('component', name),
            'description': comp_cfg.get('description', ''),
            'status': comp_cfg.get('status', 'defined') or 'defined',
            'agent': comp_cfg.get('agent', ''),
            'model': comp_cfg.get('model', ''),
            'orbit': 0,
            'sensors': [],
            'delivers': comp_cfg.get('delivers', []),
            'has_preflight': bool(comp_cfg.get('preflight')),
            'has_postflight': bool(comp_cfg.get('postflight')),
            'has_retry': bool(comp_cfg.get('retry')),
            'max_orbits': 0,
        }
        sensors = comp_cfg.get('sensors', {})
        if sensors:
            cs['sensors'] = sensors.get('paths', [])
        orbits = comp_cfg.get('orbits', {})
        if isinstance(orbits, dict) and orbits.get('max'):
            cs['max_orbits'] = orbits['max']

        # Check runtime
        state_data = self._load_json(os.path.join(self.state_dir, 'state.json')) or {}
        for c in state_data.get('components', []):
            if c.get('name') == name:
                cs['status'] = c.get('status', cs['status'])
                cs['orbit'] = c.get('orbit', 0)
                break

        return cs

    def build_runs(self, mission_filter=''):
        """Return run summaries, optionally filtered."""
        runs = self._load_runs()
        result = []
        for run in runs:
            if not run.get('_run_id'):
                continue
            m_name = run.get('mission', '')
            if mission_filter and m_name != mission_filter:
                continue

            rs = {
                'id': run['_run_id'],
                'name': m_name,
                'status': run.get('status', 'defined'),
                'created_at': run.get('started_at', ''),
                'updated_at': run.get('updated_at', ''),
                'stages': [],
            }
            for s in run.get('_stages', []):
                rs['stages'].append({
                    'name': s.get('name', ''),
                    'component': s.get('component', ''),
                    'status': s.get('status', 'pending'),
                    'orbit': s.get('orbit', 0),
                    'max_orbits': s.get('max_orbits', 0),
                    'orbits_to': s.get('orbits_to', ''),
                    'depends_on': s.get('depends_on', []),
                })
            result.append(rs)

        # Sort newest first
        result.sort(key=lambda x: x.get('created_at', ''), reverse=True)
        return result

    def build_run_detail(self, run_id):
        """Return detail for a single run."""
        runs = self._load_runs()
        for run in runs:
            if run.get('_run_id') == run_id:
                rs = {
                    'id': run_id,
                    'name': run.get('mission', ''),
                    'status': run.get('status', 'defined'),
                    'created_at': run.get('started_at', ''),
                    'updated_at': run.get('updated_at', ''),
                    'stages': [],
                }
                for s in run.get('_stages', []):
                    rs['stages'].append({
                        'name': s.get('name', ''),
                        'component': s.get('component', ''),
                        'status': s.get('status', 'pending'),
                        'orbit': s.get('orbit', 0),
                        'max_orbits': s.get('max_orbits', 0),
                    })
                return rs
        return None

    def build_sensors(self):
        """Return sensor summaries from component configs."""
        components = self._load_component_configs()
        result = []
        for c_name, comp_cfg in components.items():
            sensors = comp_cfg.get('sensors', {})
            if not sensors:
                continue
            paths = sensors.get('paths', [])
            if not paths:
                continue
            result.append({
                'type': 'component',
                'name': c_name,
                'patterns': paths,
                'offline': False,
            })
        return result

    def build_flight_rules(self):
        """Return flight rules grouped by mission."""
        missions = self._load_mission_configs()
        result = {}
        for m_name, mc in missions.items():
            rules = mc.get('flight_rules', [])
            if rules:
                result[m_name] = [{
                    'name': r.get('name', ''),
                    'condition': r.get('condition', ''),
                    'check_interval': r.get('check_interval', ''),
                    'on_violation': r.get('on_violation', ''),
                    'message': r.get('message', ''),
                } for r in rules]
        return result

    def build_telemetry(self):
        """Return per-component telemetry summaries."""
        entries = self._load_telemetry()
        by_comp = {}
        for e in entries:
            comp = e.get('component', '')
            if comp not in by_comp:
                by_comp[comp] = {'invocations': 0, 'total_tokens': 0, 'total_duration': 0.0}
            s = by_comp[comp]
            s['invocations'] += 1
            s['total_tokens'] += e.get('tokens', 0)
            s['total_duration'] += e.get('duration', 0) * 1000  # s to ms

        result = []
        for comp, s in sorted(by_comp.items()):
            avg_dur = s['total_duration'] / s['invocations'] if s['invocations'] > 0 else 0
            result.append({
                'component': comp,
                'invocations': s['invocations'],
                'total_tokens': s['total_tokens'],
                'avg_duration_ms': avg_dur,
            })
        return result

    def build_costs(self):
        """Return costs breakdown."""
        entries = self._load_telemetry()
        if not entries:
            return {'totals': {'invocations': 0, 'tokens': 0, 'cost': 0},
                    'by_model': [], 'by_component': [], 'by_stage': [],
                    'by_mission': [], 'by_run': []}

        total_tokens = sum(e.get('tokens', 0) for e in entries)
        total_cost = sum(e.get('cost', 0) for e in entries)

        # By model
        by_model = {}
        for e in entries:
            model = e.get('model', 'unknown')
            if model not in by_model:
                by_model[model] = {'model': model, 'invocations': 0, 'tokens': 0,
                                   'cost': 0, 'token_usage': {}}
            m = by_model[model]
            m['invocations'] += 1
            m['tokens'] += e.get('tokens', 0)
            m['cost'] += e.get('cost', 0)
            tu = m['token_usage']
            tu['input_tokens'] = tu.get('input_tokens', 0) + e.get('input_tokens', 0)
            tu['output_tokens'] = tu.get('output_tokens', 0) + e.get('output_tokens', 0)
            tu['cache_creation_input_tokens'] = tu.get('cache_creation_input_tokens', 0) + e.get('cache_creation_input_tokens', 0)
            tu['cache_read_input_tokens'] = tu.get('cache_read_input_tokens', 0) + e.get('cache_read_input_tokens', 0)

        # By component
        by_component = {}
        for e in entries:
            comp = e.get('component', 'unknown')
            if comp not in by_component:
                by_component[comp] = {'component': comp, 'invocations': 0,
                                      'tokens': 0, 'cost': 0}
            c = by_component[comp]
            c['invocations'] += 1
            c['tokens'] += e.get('tokens', 0)
            c['cost'] += e.get('cost', 0)

        # By stage
        by_stage = {}
        for e in entries:
            stage = e.get('stage', '')
            if not stage:
                continue
            if stage not in by_stage:
                by_stage[stage] = {'stage': stage, 'invocations': 0, 'tokens': 0,
                                   'cost': 0, 'total_duration': 0}
            s = by_stage[stage]
            s['invocations'] += 1
            s['tokens'] += e.get('tokens', 0)
            s['cost'] += e.get('cost', 0)
            s['total_duration'] += e.get('duration', 0)

        by_stage_list = []
        for s in by_stage.values():
            avg = s['total_duration'] / s['invocations'] if s['invocations'] > 0 else 0
            by_stage_list.append({
                'stage': s['stage'], 'invocations': s['invocations'],
                'tokens': s['tokens'], 'cost': s['cost'],
                'avg_duration_seconds': avg,
            })

        # By mission
        by_mission = {}
        for e in entries:
            mission = e.get('mission', '')
            if not mission:
                continue
            if mission not in by_mission:
                by_mission[mission] = {'mission': mission, 'invocations': 0,
                                       'tokens': 0, 'cost': 0}
            m = by_mission[mission]
            m['invocations'] += 1
            m['tokens'] += e.get('tokens', 0)
            m['cost'] += e.get('cost', 0)

        # By run
        by_run = {}
        for e in entries:
            run_id = e.get('run_id', '')
            if not run_id:
                continue
            if run_id not in by_run:
                by_run[run_id] = {'run_id': run_id, 'mission': e.get('mission', ''),
                                  'invocations': 0, 'tokens': 0, 'cost': 0}
            r = by_run[run_id]
            r['invocations'] += 1
            r['tokens'] += e.get('tokens', 0)
            r['cost'] += e.get('cost', 0)

        return {
            'totals': {
                'invocations': len(entries),
                'tokens': total_tokens,
                'cost': total_cost,
            },
            'by_model': list(by_model.values()),
            'by_component': list(by_component.values()),
            'by_stage': by_stage_list,
            'by_mission': list(by_mission.values()),
            'by_run': list(by_run.values()),
        }

    def build_modules(self):
        """Return module summaries from modules/*.yaml configs."""
        modules = self._load_module_configs()
        result = []
        for m_name, mc in modules.items():
            mod = {
                'name': mc.get('module', m_name),
                'description': mc.get('description', ''),
                'status': mc.get('status', 'active'),
                'parameters': {},
                'stages': [],
                'delivers': mc.get('delivers', []),
            }
            # Parameters
            params = mc.get('parameters', {})
            if isinstance(params, dict):
                for p_name, p_cfg in params.items():
                    if isinstance(p_cfg, dict):
                        mod['parameters'][p_name] = {
                            'required': p_cfg.get('required', False),
                            'description': p_cfg.get('description', ''),
                            'default': p_cfg.get('default', ''),
                        }
                    else:
                        mod['parameters'][p_name] = {'required': False, 'description': str(p_cfg), 'default': ''}
            # Stages
            for s in mc.get('stages', []):
                mod['stages'].append({
                    'name': s.get('name', ''),
                    'component': s.get('component', ''),
                    'depends_on': s.get('depends_on', []),
                })
            result.append(mod)
        result.sort(key=lambda x: x['name'])
        return result

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def _stage_summary_from_config(self, s):
        return {
            'name': s.get('name', ''),
            'component': s.get('component', ''),
            'status': 'defined',
            'orbit': 0,
            'max_orbits': s.get('max_orbits', 0),
            'orbits_to': s.get('orbits_to', ''),
            'depends_on': s.get('depends_on', []),
            'waypoint': s.get('waypoint', False),
            'stage_type': s.get('type', ''),
        }
