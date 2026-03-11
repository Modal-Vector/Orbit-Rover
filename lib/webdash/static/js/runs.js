// Runs table view for the Orbit dashboard

const Runs = {
    container: null,
    graphContainer: null,
    active: false,

    init() {
        this.container = document.getElementById('runs-container');
        this.graphContainer = document.getElementById('graph-container');
    },

    async show(missionFilter) {
        if (!this.container) return;
        this.active = true;

        // Toggle visibility
        this.container.classList.remove('hidden');
        if (this.graphContainer) {
            this.graphContainer.classList.add('hidden');
        }

        // Update tab state
        document.querySelectorAll('.view-tab').forEach(t => t.classList.remove('active'));
        const runsTab = document.getElementById('tab-runs');
        if (runsTab) runsTab.classList.add('active');

        // Show loading
        this.container.innerHTML = '<p class="loading" style="padding: 20px; color: var(--text-muted);">Loading runs...</p>';

        try {
            const runs = await API.fetchRuns(missionFilter || '');
            this.renderTable(runs);
        } catch (err) {
            this.container.innerHTML = '<p style="padding: 20px; color: var(--led-failed);">Failed to load runs</p>';
        }
    },

    hide() {
        if (!this.container) return;
        this.active = false;

        this.container.classList.add('hidden');
        if (this.graphContainer) {
            this.graphContainer.classList.remove('hidden');
        }

        // Update tab state
        document.querySelectorAll('.view-tab').forEach(t => t.classList.remove('active'));
        const graphTab = document.getElementById('tab-graph');
        if (graphTab) graphTab.classList.add('active');
    },

    renderTable(runs) {
        if (!this.container) return;

        const filterValue = this.container.querySelector('.runs-filter')
            ? this.container.querySelector('.runs-filter').value
            : '';

        let html = `
            <div class="runs-header">
                <input type="text" class="runs-filter" placeholder="Filter by mission name..." value="${this.escapeAttr(filterValue)}">
                <span class="runs-count">${runs.length} run(s)</span>
            </div>
            <table class="runs-table">
                <thead>
                    <tr>
                        <th class="runs-th-status"></th>
                        <th>Mission</th>
                        <th>Run ID</th>
                        <th>Started</th>
                        <th>Stages</th>
                    </tr>
                </thead>
                <tbody>
        `;

        if (runs.length === 0) {
            html += '<tr><td colspan="5" class="runs-empty">No runs found</td></tr>';
        } else {
            for (const run of runs) {
                const stageDots = (run.stages || []).map(s =>
                    `<span class="stage-mini-dot ${s.status || 'pending'}" title="${this.escapeAttr(s.name)}: ${s.status || 'pending'}"></span>`
                ).join('');

                html += `
                    <tr class="run-row" data-run-id="${this.escapeAttr(run.id)}">
                        <td><span class="status-dot ${run.status || 'defined'}"></span></td>
                        <td class="run-mission">${this.escapeHtml(run.name)}</td>
                        <td class="run-id">${this.escapeHtml(this.truncateID(run.id))}</td>
                        <td class="run-time">${this.formatTime(run.created_at)}</td>
                        <td class="run-stages">${(run.stages || []).length} ${stageDots}</td>
                    </tr>
                `;
            }
        }

        html += '</tbody></table>';
        this.container.innerHTML = html;

        // Bind filter input
        const filterInput = this.container.querySelector('.runs-filter');
        if (filterInput) {
            filterInput.addEventListener('input', () => {
                this.filterRows(filterInput.value);
            });
            filterInput.focus();
        }

        // Bind row clicks
        this.container.querySelectorAll('.run-row').forEach(row => {
            row.addEventListener('click', () => {
                const runID = row.dataset.runId;
                this.showRunDetail(runID);
            });
        });
    },

    filterRows(query) {
        const lowerQuery = query.toLowerCase();
        this.container.querySelectorAll('.run-row').forEach(row => {
            const mission = row.querySelector('.run-mission').textContent.toLowerCase();
            const id = row.querySelector('.run-id').textContent.toLowerCase();
            if (mission.includes(lowerQuery) || id.includes(lowerQuery)) {
                row.style.display = '';
            } else {
                row.style.display = 'none';
            }
        });
    },

    async showRunDetail(runID) {
        try {
            const run = await API.fetchRunDetail(runID);
            if (!run) return;

            const content = document.getElementById('detail-content');
            if (!content) return;

            const stageDots = (run.stages || []).map(s =>
                `<span class="stage-mini-dot ${s.status || 'pending'}" title="${this.escapeAttr(s.name)}"></span>`
            ).join('');

            let stagesHtml = '';
            if (run.stages && run.stages.length > 0) {
                stagesHtml = `
                    <div class="detail-section">
                        <h3>Stages (${run.stages.length})</h3>
                        <ul class="detail-list">
                            ${run.stages.map(s => `
                                <li class="stage-item">
                                    <span class="stage-status ${s.status || 'pending'}"></span>
                                    <span class="stage-name">${this.escapeHtml(s.name)}</span>
                                    <span class="stage-orbit">${Panels.formatOrbit(s)}</span>
                                </li>
                            `).join('')}
                        </ul>
                    </div>
                `;
            }

            content.innerHTML = `
                <div class="detail-type">Run</div>
                <h2>${this.escapeHtml(run.name)}</h2>
                <span class="detail-status ${run.status || 'defined'}">${run.status || 'defined'}</span>
                <div class="detail-section">
                    <dl class="detail-kv">
                        <dt>Run ID</dt>
                        <dd>${this.escapeHtml(run.id)}</dd>
                        <dt>Started</dt>
                        <dd>${this.formatTime(run.created_at)}</dd>
                        ${run.updated_at ? `<dt>Updated</dt><dd>${this.formatTime(run.updated_at)}</dd>` : ''}
                    </dl>
                </div>
                ${stagesHtml}
            `;

            Panels.show();
        } catch (err) {
            console.error('Failed to load run detail:', err);
        }
    },

    truncateID(id) {
        if (!id) return '-';
        if (id.length <= 16) return id;
        return id.substring(0, 8) + '...' + id.substring(id.length - 4);
    },

    formatTime(timestamp) {
        if (!timestamp) return '-';
        try {
            const date = new Date(timestamp);
            return date.toLocaleString();
        } catch {
            return timestamp;
        }
    },

    escapeHtml(text) {
        if (!text) return '';
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    },

    escapeAttr(text) {
        if (!text) return '';
        return text.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    }
};
