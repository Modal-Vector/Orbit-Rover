// Detail panel management for the Orbit dashboard

const Panels = {
    panel: null,
    content: null,
    closeBtn: null,

    // Initialize panels
    init() {
        this.panel = document.getElementById('detail-panel');
        this.content = document.getElementById('detail-content');
        this.closeBtn = document.getElementById('close-panel');

        if (this.closeBtn) {
            this.closeBtn.addEventListener('click', () => this.hide());
        }

        // Keyboard handler — Escape closes detail panel
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape') {
                this.hide();
            }
        });
    },

    // Show the detail panel
    show() {
        if (this.panel) {
            this.panel.classList.remove('hidden');
        }
    },

    // Hide the detail panel
    hide() {
        if (this.panel) {
            this.panel.classList.add('hidden');
        }
        if (Graph && Graph.cy) {
            Graph.cy.elements().unselect();
        }
    },

    // Show details for a node
    showNodeDetail(nodeData) {
        if (!this.content) return;

        let html = '';

        switch (nodeData.type) {
            case 'mission':
                html = this.renderMissionDetail(nodeData);
                break;
            case 'module':
                html = this.renderModuleDetail(nodeData);
                break;
            case 'stage':
                html = this.renderStageDetail(nodeData);
                break;
            case 'component':
                html = this.renderComponentDetail(nodeData);
                break;
            case 'sensor':
                html = this.renderSensorDetail(nodeData);
                break;
            default:
                html = this.renderGenericDetail(nodeData);
        }

        this.content.innerHTML = html;
        this.show();

        // Load additional details via API
        this.loadDetails(nodeData);
    },

    // Render mission detail
    renderMissionDetail(data) {
        return `
            <div class="detail-type">Mission</div>
            <h2>${data.label}</h2>
            <span class="detail-status ${data.status || 'defined'}">${data.status || 'defined'}</span>
            ${data.has_flight_rules ? `<div class="detail-section"><span class="badge badge-warn">${data.flight_rule_count} flight rule(s)</span></div>` : ''}
            ${data.started_at ? `<div class="detail-section">
                <h3>Started</h3>
                <p>${this.formatTime(data.started_at)}</p>
            </div>` : ''}
            <div class="detail-section" id="mission-stages">
                <h3>Stages</h3>
                <p class="loading">Loading...</p>
            </div>
            <div class="detail-section" id="mission-sensors"></div>
            <div class="detail-section" id="mission-flight-rules"></div>
            <div class="detail-section" id="mission-runs"></div>
        `;
    },

    // Render module detail
    renderModuleDetail(data) {
        return `
            <div class="detail-type">Module</div>
            <h2>${data.label}</h2>
            <span class="detail-status ${data.status || 'defined'}">${data.status || 'defined'}</span>
            <div class="detail-section" id="module-description"></div>
            <div class="detail-section" id="module-stages">
                <h3>Stages</h3>
                <p class="loading">Loading...</p>
            </div>
        `;
    },

    // Render stage detail
    renderStageDetail(data) {
        const orbit = data.orbit || 0;
        const maxOrbits = data.max_orbits || 0;
        const orbitText = maxOrbits > 0 ? `${orbit}/${maxOrbits}` : `${orbit}`;

        let badges = '';
        if (data.waypoint) {
            badges += '<span class="badge badge-waypoint">waypoint</span> ';
        }
        if (data.stage_type === 'manual') {
            badges += '<span class="badge badge-preflight">manual</span> ';
        }

        return `
            <div class="detail-type">Stage</div>
            <h2>${data.label}</h2>
            <span class="detail-status ${data.status || 'pending'}">${data.status || 'pending'}</span>
            ${badges ? `<div class="detail-section">${badges}</div>` : ''}
            <div class="detail-section">
                <dl class="detail-kv">
                    <dt>Component</dt>
                    <dd>${data.component || '-'}</dd>
                    <dt>Orbits</dt>
                    <dd>${orbitText}</dd>
                    ${data.orbits_to ? `<dt>Orbits To</dt><dd>${data.orbits_to}</dd>` : ''}
                    ${data.stage_type ? `<dt>Type</dt><dd>${data.stage_type}</dd>` : ''}
                </dl>
            </div>
            <div class="detail-section" id="stage-extra"></div>
        `;
    },

    // Render component detail
    renderComponentDetail(data) {
        let lifecycleBadges = '';
        if (data.has_preflight) {
            lifecycleBadges += '<span class="badge badge-preflight">preflight</span> ';
        }
        if (data.has_postflight) {
            lifecycleBadges += '<span class="badge badge-postflight">postflight</span> ';
        }
        if (data.has_retry) {
            lifecycleBadges += '<span class="badge badge-retry">retry</span> ';
        }

        let deliversHtml = '';
        if (data.delivers && data.delivers.length > 0) {
            deliversHtml = `
                <div class="detail-section">
                    <h3>Delivers</h3>
                    <ul class="detail-list">
                        ${data.delivers.map(d => `<li><code>${this.escapeHtml(d)}</code></li>`).join('')}
                    </ul>
                </div>
            `;
        }

        const maxOrbits = data.max_orbits || 0;

        return `
            <div class="detail-type">Component</div>
            <h2>${data.label}</h2>
            <span class="detail-status ${data.status || 'defined'}">${data.status || 'defined'}</span>
            ${lifecycleBadges ? `<div class="detail-section">${lifecycleBadges}</div>` : ''}
            <div class="detail-section" id="component-details">
                <dl class="detail-kv">
                    <dt>Orbit</dt>
                    <dd>${data.orbit || 0}${maxOrbits > 0 ? '/' + maxOrbits : ''}</dd>
                </dl>
            </div>
            ${deliversHtml}
            <div class="detail-section" id="component-sensors"></div>
            <div class="detail-section" id="component-costs"></div>
        `;
    },

    // Render sensor detail
    renderSensorDetail(data) {
        const patterns = data.patterns || [];
        // Extract entity type from node ID (sensor:{entityType}:{name})
        // because convertToElements overwrites data.type with "sensor"
        const idParts = (data.id || '').split(':');
        const entityType = idParts.length >= 3 ? idParts[1] : 'unknown';
        const targetName = data.target || (idParts.length >= 3 ? idParts.slice(2).join(':') : data.label);

        return `
            <div class="detail-type">Sensor</div>
            <h2>${this.escapeHtml(targetName)}</h2>
            <span class="detail-status ${data.status || 'active'}">${data.status || 'active'}</span>
            <div class="detail-section">
                <dl class="detail-kv">
                    <dt>Target Type</dt>
                    <dd>${this.escapeHtml(entityType)}</dd>
                    <dt>Target</dt>
                    <dd>${this.escapeHtml(targetName)}</dd>
                </dl>
            </div>
            ${patterns.length > 0 ? `
                <div class="detail-section">
                    <h3>Patterns (${patterns.length})</h3>
                    <ul class="detail-list">
                        ${patterns.map(p => `<li><code>${this.escapeHtml(p)}</code></li>`).join('')}
                    </ul>
                </div>
            ` : ''}
            <div class="detail-section" id="sensor-extra"></div>
        `;
    },

    // Render generic detail
    renderGenericDetail(data) {
        return `
            <div class="detail-type">${data.type || 'Node'}</div>
            <h2>${data.label}</h2>
            <span class="detail-status ${data.status || 'unknown'}">${data.status || 'unknown'}</span>
        `;
    },

    // Load additional details via API
    async loadDetails(nodeData) {
        try {
            switch (nodeData.type) {
                case 'mission':
                    await Promise.all([
                        this.loadMissionStages(nodeData),
                        this.loadMissionFlightRules(nodeData),
                        this.loadMissionRuns(nodeData),
                        this.loadMissionSensors(nodeData),
                    ]);
                    break;
                case 'module':
                    await this.loadModuleDetails(nodeData);
                    break;
                case 'stage':
                    await this.loadStageDetails(nodeData);
                    break;
                case 'component':
                    await Promise.all([
                        this.loadComponentDetails(nodeData),
                        this.loadComponentTelemetry(nodeData),
                        this.loadComponentCosts(nodeData),
                    ]);
                    break;
                case 'sensor':
                    await this.loadSensorDetails(nodeData);
                    break;
            }
        } catch (err) {
            console.error('Failed to load details:', err);
        }
    },

    // Load mission stages
    async loadMissionStages(nodeData) {
        const container = document.getElementById('mission-stages');
        if (!container) return;

        try {
            // Extract mission name from node data
            const missionName = nodeData.name || nodeData.id.replace('mission:', '').split(':')[0];
            const mission = await API.fetchMissionDetail(missionName);

            if (mission && mission.stages) {
                container.innerHTML = `
                    <h3>Stages (${mission.stages.length})</h3>
                    <ul class="detail-list">
                        ${mission.stages.map(s => `
                            <li class="stage-item">
                                <span class="stage-status ${s.status || 'pending'}"></span>
                                <span class="stage-name">${s.name}${s.waypoint ? ' <span class="badge badge-waypoint">wp</span>' : ''}</span>
                                <span class="stage-orbit">${this.formatOrbit(s)}</span>
                            </li>
                        `).join('')}
                    </ul>
                `;
            }
        } catch (err) {
            container.innerHTML = '<h3>Stages</h3><p>Failed to load stages</p>';
        }
    },

    // Load component details
    async loadComponentDetails(nodeData) {
        const container = document.getElementById('component-details');
        if (!container) return;

        try {
            const name = nodeData.label || nodeData.id.split(':').pop();
            const comp = await API.fetchComponentDetail(name);

            if (comp) {
                const maxOrbits = comp.max_orbits || 0;

                let lifecycleBadges = '';
                if (comp.has_preflight) lifecycleBadges += '<span class="badge badge-preflight">preflight</span> ';
                if (comp.has_postflight) lifecycleBadges += '<span class="badge badge-postflight">postflight</span> ';
                if (comp.has_retry) lifecycleBadges += '<span class="badge badge-retry">retry</span> ';

                container.innerHTML = `
                    <dl class="detail-kv">
                        <dt>Agent</dt>
                        <dd>${comp.agent || '-'}</dd>
                        <dt>Model</dt>
                        <dd>${comp.model || '-'}</dd>
                        <dt>Orbit</dt>
                        <dd>${comp.orbit || 0}${maxOrbits > 0 ? '/' + maxOrbits : ''}</dd>

                    </dl>
                    ${lifecycleBadges ? `<div style="margin-top: 8px">${lifecycleBadges}</div>` : ''}
                    ${comp.delivers && comp.delivers.length > 0 ? `
                        <div class="detail-section" style="margin-top: 12px">
                            <h3>Delivers</h3>
                            <ul class="detail-list">
                                ${comp.delivers.map(d => `<li><code>${this.escapeHtml(d)}</code></li>`).join('')}
                            </ul>
                        </div>
                    ` : ''}
                `;

                // Populate sensor patterns section
                const sensorsContainer = document.getElementById('component-sensors');
                if (sensorsContainer && comp.sensors && comp.sensors.length > 0) {
                    sensorsContainer.innerHTML = `
                        <h3>Sensor Patterns (${comp.sensors.length})</h3>
                        <ul class="detail-list">
                            ${comp.sensors.map(s => `<li><code>${this.escapeHtml(s)}</code></li>`).join('')}
                        </ul>
                    `;
                }
            }
        } catch (err) {
            // Keep existing content on error
        }
    },

    // Load mission flight rules
    async loadMissionFlightRules(nodeData) {
        const container = document.getElementById('mission-flight-rules');
        if (!container) return;

        try {
            const missionName = nodeData.name || nodeData.id.replace('mission:', '').split(':')[0];
            const mission = await API.fetchMissionDetail(missionName);

            if (mission && mission.flight_rules && mission.flight_rules.length > 0) {
                const severityClass = (action) => {
                    if (action === 'abort') return 'badge-abort';
                    if (action === 'hold' || action === 'pause') return 'badge-hold';
                    return 'badge-warn';
                };

                container.innerHTML = `
                    <h3>Flight Rules (${mission.flight_rules.length})</h3>
                    <ul class="detail-list">
                        ${mission.flight_rules.map(r => `
                            <li>
                                <div>${this.escapeHtml(r.name)}</div>
                                <span class="badge ${severityClass(r.on_violation)}">${r.on_violation}</span>
                                ${r.message ? `<div style="font-size: 10px; color: var(--text-muted); margin-top: 2px">${this.escapeHtml(r.message)}</div>` : ''}
                            </li>
                        `).join('')}
                    </ul>
                `;
            }
        } catch (err) {
            // No flight rules, that's OK
        }
    },

    // Load mission run history
    async loadMissionRuns(nodeData) {
        const container = document.getElementById('mission-runs');
        if (!container) return;

        try {
            const missionName = nodeData.name || nodeData.id.replace('mission:', '').split(':')[0];
            const runs = await API.fetchRuns(missionName);

            if (runs && runs.length > 0) {
                container.innerHTML = `
                    <h3>Run History (${runs.length})</h3>
                    <ul class="detail-list">
                        ${runs.map(r => `
                            <li class="run-history-item" data-run-id="${this.escapeHtml(r.id)}">
                                <span class="stage-status ${r.status || 'defined'}"></span>
                                <span class="run-history-id">${this.escapeHtml(r.id.length > 12 ? r.id.substring(0, 8) + '...' : r.id)}</span>
                                <span class="run-history-time">${this.formatTime(r.created_at)}</span>
                            </li>
                        `).join('')}
                    </ul>
                `;

                // Bind click handlers for run history items
                container.querySelectorAll('.run-history-item').forEach(item => {
                    item.style.cursor = 'pointer';
                    item.addEventListener('click', () => {
                        const runID = item.dataset.runId;
                        if (typeof Runs !== 'undefined') {
                            Runs.showRunDetail(runID);
                        }
                    });
                });
            } else {
                container.innerHTML = '';
            }
        } catch (err) {
            // No run history, that's OK
        }
    },

    // Load component telemetry
    async loadComponentTelemetry(nodeData) {
        try {
            const response = await fetch('/api/telemetry');
            if (!response.ok) return;

            const telemetry = await response.json();
            const compName = nodeData.label || nodeData.id.split(':').pop();
            const tel = telemetry.find(t => t.component === compName);

            if (!tel) return;

            // Append telemetry section to detail content
            const content = document.getElementById('detail-content');
            if (!content) return;

            const section = document.createElement('div');
            section.className = 'detail-section';
            section.innerHTML = `
                <h3>Telemetry</h3>
                <dl class="detail-kv">
                    <dt>Invocations</dt>
                    <dd class="telemetry-value">${tel.invocations}</dd>
                    <dt>Tokens</dt>
                    <dd class="telemetry-value">${this.formatLargeNumber(tel.total_tokens)}</dd>
                    <dt>Avg Duration</dt>
                    <dd class="telemetry-value">${Math.round(tel.avg_duration_ms)}ms</dd>
                </dl>
            `;
            content.appendChild(section);

        } catch (err) {
            // Telemetry unavailable, skip
        }
    },

    // Load mission sensors
    async loadMissionSensors(nodeData) {
        const container = document.getElementById('mission-sensors');
        if (!container) return;

        try {
            const missionName = nodeData.name || nodeData.id.replace('mission:', '').split(':')[0];
            const sensors = await API.fetchSensors();

            if (sensors && sensors.length > 0) {
                const matching = sensors.filter(s => s.type === 'mission' && s.name === missionName);
                if (matching.length > 0) {
                    container.innerHTML = `
                        <h3>Sensors (${matching.length})</h3>
                        <ul class="detail-list">
                            ${matching.map(s => `
                                <li>
                                    ${s.offline ? '<span class="badge" style="background: var(--led-offline)">offline</span> ' : ''}
                                    ${s.patterns.map(p => `<code>${this.escapeHtml(p)}</code>`).join(', ')}
                                </li>
                            `).join('')}
                        </ul>
                    `;
                }
            }
        } catch (err) {
            // Sensors unavailable, skip
        }
    },

    // Load module details (description + stages)
    async loadModuleDetails(nodeData) {
        const descContainer = document.getElementById('module-description');
        const stagesContainer = document.getElementById('module-stages');

        try {
            const modules = await API.fetchModules();
            const moduleName = nodeData.name || nodeData.id.replace('module:', '').split(':')[0];
            const mod = modules && modules.find(m => m.name === moduleName);

            if (mod) {
                if (descContainer && mod.description) {
                    descContainer.innerHTML = `<p style="color: var(--text-muted)">${this.escapeHtml(mod.description)}</p>`;
                }

                if (stagesContainer && mod.stages && mod.stages.length > 0) {
                    stagesContainer.innerHTML = `
                        <h3>Stages (${mod.stages.length})</h3>
                        <ul class="detail-list">
                            ${mod.stages.map(s => `
                                <li class="stage-item">
                                    <span class="stage-status ${s.status || 'pending'}"></span>
                                    <span class="stage-name">${s.name}${s.waypoint ? ' <span class="badge badge-waypoint">wp</span>' : ''}</span>
                                    <span class="stage-orbit">${this.formatOrbit(s)}</span>
                                </li>
                            `).join('')}
                        </ul>
                    `;
                } else if (stagesContainer) {
                    stagesContainer.innerHTML = '<h3>Stages</h3><p style="color: var(--text-muted)">No stages defined</p>';
                }
            } else if (stagesContainer) {
                stagesContainer.innerHTML = '<h3>Stages</h3><p>Module not found</p>';
            }
        } catch (err) {
            if (stagesContainer) {
                stagesContainer.innerHTML = '<h3>Stages</h3><p>Failed to load stages</p>';
            }
        }
    },

    // Load stage details (dependencies + module origin)
    async loadStageDetails(nodeData) {
        const container = document.getElementById('stage-extra');
        if (!container) return;

        try {
            // Parse mission name from stage ID: stage:{mission}:{stage}
            const idParts = (nodeData.id || '').split(':');
            if (idParts.length < 3) return;
            const missionName = idParts[1];

            const mission = await API.fetchMissionDetail(missionName);
            if (!mission || !mission.stages) return;

            const stageName = idParts.slice(2).join(':');
            const stage = mission.stages.find(s => s.name === stageName);
            if (!stage) return;

            let html = '';

            // Show module origin if present
            if (stage.module_name) {
                html += `
                    <dl class="detail-kv">
                        <dt>Module</dt>
                        <dd>${this.escapeHtml(stage.module_name)}</dd>
                    </dl>
                `;
            }

            // Show dependencies
            if (stage.depends_on && stage.depends_on.length > 0) {
                html += `
                    <h3>Dependencies (${stage.depends_on.length})</h3>
                    <ul class="detail-list">
                        ${stage.depends_on.map(dep => {
                            const depStatus = this.getStageDependencyStatus(dep, mission.stages);
                            return `
                                <li class="stage-item">
                                    <span class="stage-status ${depStatus}"></span>
                                    <span class="stage-name">${this.escapeHtml(dep)}</span>
                                </li>
                            `;
                        }).join('')}
                    </ul>
                `;
            }

            if (html) {
                container.innerHTML = html;
            }
        } catch (err) {
            // Stage details unavailable, skip
        }
    },

    // Get the status of a dependency stage
    getStageDependencyStatus(stageName, stages) {
        if (!stages) return 'defined';
        const stage = stages.find(s => s.name === stageName);
        return stage ? (stage.status || 'defined') : 'defined';
    },

    // Load component cost data
    async loadComponentCosts(nodeData) {
        const container = document.getElementById('component-costs');
        if (!container) return;

        try {
            const costs = await API.fetchCosts();
            if (!costs || !costs.by_component) return;

            const compName = nodeData.name || nodeData.label || nodeData.id.split(':').pop();
            const comp = costs.by_component.find(c => c.component === compName);
            if (!comp || comp.invocations === 0) return;

            container.innerHTML = `
                <h3>Costs</h3>
                <dl class="detail-kv">
                    <dt>Invocations</dt>
                    <dd class="telemetry-value">${comp.invocations}</dd>
                    <dt>Tokens</dt>
                    <dd class="telemetry-value">${this.formatLargeNumber(comp.tokens)}</dd>
                    <dt>Cost</dt>
                    <dd class="telemetry-value">$${comp.cost.toFixed(4)}</dd>
                </dl>
            `;
        } catch (err) {
            // Costs unavailable, skip
        }
    },

    // Load sensor details (offline status + trigger description)
    async loadSensorDetails(nodeData) {
        const container = document.getElementById('sensor-extra');
        if (!container) return;

        try {
            const sensors = await API.fetchSensors();
            if (!sensors) return;

            // Parse entity type and target name from ID
            const idParts = (nodeData.id || '').split(':');
            const entityType = idParts.length >= 3 ? idParts[1] : '';
            const targetName = idParts.length >= 3 ? idParts.slice(2).join(':') : '';

            const sensor = sensors.find(s => s.name === targetName && s.type === entityType);
            if (!sensor) return;

            let html = '';

            if (sensor.offline) {
                html += '<div style="margin-bottom: 8px"><span class="badge" style="background: var(--led-offline)">offline</span></div>';
            }

            // Trigger description
            if (entityType === 'mission') {
                html += `<p style="color: var(--text-muted)">Launches mission <strong>${this.escapeHtml(targetName)}</strong> on file changes</p>`;
            } else if (entityType === 'component') {
                html += `<p style="color: var(--text-muted)">Triggers component <strong>${this.escapeHtml(targetName)}</strong> on file changes</p>`;
            }

            if (html) {
                container.innerHTML = html;
            }
        } catch (err) {
            // Sensor details unavailable, skip
        }
    },

    // Format large numbers
    formatLargeNumber(n) {
        if (n >= 1000000) return (n / 1000000).toFixed(1) + 'M';
        if (n >= 1000) return (n / 1000).toFixed(1) + 'K';
        return n.toString();
    },

    // Format orbit display
    formatOrbit(stage) {
        if (stage.max_orbits > 0) {
            return `${stage.orbit || 0}/${stage.max_orbits}`;
        }
        if (stage.orbit > 0) {
            return `${stage.orbit}`;
        }
        return '';
    },

    // Format timestamp
    formatTime(timestamp) {
        if (!timestamp) return '-';
        try {
            const date = new Date(timestamp);
            return date.toLocaleString();
        } catch {
            return timestamp;
        }
    },

    // Escape HTML
    escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }
};
