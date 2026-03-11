// Costs tab view for the Orbit dashboard

const Costs = {
    container: null,
    graphContainer: null,
    active: false,

    init() {
        this.container = document.getElementById('costs-container');
        this.graphContainer = document.getElementById('graph-container');
    },

    async show() {
        if (!this.container) return;
        this.active = true;

        // Toggle visibility
        this.container.classList.remove('hidden');
        if (this.graphContainer) {
            this.graphContainer.classList.add('hidden');
        }

        // Hide runs container too
        const runsContainer = document.getElementById('runs-container');
        if (runsContainer) runsContainer.classList.add('hidden');

        // Update tab state
        document.querySelectorAll('.view-tab').forEach(t => t.classList.remove('active'));
        const costsTab = document.getElementById('tab-costs');
        if (costsTab) costsTab.classList.add('active');

        // Show loading
        this.container.innerHTML = '<p class="loading" style="padding: 20px; color: var(--text-muted);">Loading costs...</p>';

        try {
            const data = await this.fetchCosts();
            this.render(data);
        } catch (err) {
            this.container.innerHTML = '<p style="padding: 20px; color: var(--led-failed);">Failed to load costs</p>';
        }
    },

    hide() {
        if (!this.container) return;
        this.active = false;
        this.container.classList.add('hidden');
    },

    async fetchCosts() {
        const response = await fetch('/api/costs');
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        return await response.json();
    },

    render(data) {
        if (!this.container) return;

        const totals = data.totals || {};
        const cacheRatio = this.calcCacheRatio(data.by_model || []);

        let html = `
            <div class="costs-summary">
                <div class="cost-card">
                    <span class="cost-card-value">${this.formatCost(totals.cost || 0)}</span>
                    <span class="cost-card-label">Total Cost</span>
                </div>
                <div class="cost-card">
                    <span class="cost-card-value">${this.formatNumber(totals.tokens || 0)}</span>
                    <span class="cost-card-label">Total Tokens</span>
                </div>
                <div class="cost-card">
                    <span class="cost-card-value">${totals.invocations || 0}</span>
                    <span class="cost-card-label">Invocations</span>
                </div>
                <div class="cost-card">
                    <span class="cost-card-value">${cacheRatio}</span>
                    <span class="cost-card-label">Cache Read Ratio</span>
                </div>
            </div>
        `;

        // By Model table
        if (data.by_model && data.by_model.length > 0) {
            html += `
                <div class="costs-section">
                    <h3 class="costs-section-title">By Model</h3>
                    <table class="costs-table">
                        <thead>
                            <tr>
                                <th>Model</th>
                                <th class="num">Invocations</th>
                                <th class="num">Input</th>
                                <th class="num">Output</th>
                                <th class="num">Cache Create</th>
                                <th class="num">Cache Read</th>
                                <th class="num">Total Tokens</th>
                                <th class="num">Cost</th>
                            </tr>
                        </thead>
                        <tbody>
            `;
            for (const m of data.by_model) {
                const tu = m.token_usage || {};
                html += `
                    <tr>
                        <td class="model-name">${this.escapeHtml(m.model)}</td>
                        <td class="num">${m.invocations}</td>
                        <td class="num">${this.formatNumber(tu.input_tokens || 0)}</td>
                        <td class="num">${this.formatNumber(tu.output_tokens || 0)}</td>
                        <td class="num">${this.formatNumber(tu.cache_creation_input_tokens || 0)}</td>
                        <td class="num">${this.formatNumber(tu.cache_read_input_tokens || 0)}</td>
                        <td class="num">${this.formatNumber(m.tokens || 0)}</td>
                        <td class="num cost-value">${this.formatCost(m.cost || 0)}</td>
                    </tr>
                `;
            }
            html += '</tbody></table></div>';
        }

        // By Component table
        if (data.by_component && data.by_component.length > 0) {
            html += `
                <div class="costs-section">
                    <h3 class="costs-section-title">By Component</h3>
                    <table class="costs-table">
                        <thead>
                            <tr>
                                <th>Component</th>
                                <th class="num">Invocations</th>
                                <th class="num">Tokens</th>
                                <th class="num">Cost</th>
                            </tr>
                        </thead>
                        <tbody>
            `;
            for (const c of data.by_component) {
                html += `
                    <tr>
                        <td class="comp-name">${this.escapeHtml(c.component)}</td>
                        <td class="num">${c.invocations}</td>
                        <td class="num">${this.formatNumber(c.tokens || 0)}</td>
                        <td class="num cost-value">${this.formatCost(c.cost || 0)}</td>
                    </tr>
                `;
            }
            html += '</tbody></table></div>';
        }

        // By Stage table
        if (data.by_stage && data.by_stage.length > 0) {
            html += `
                <div class="costs-section">
                    <h3 class="costs-section-title">By Stage</h3>
                    <table class="costs-table">
                        <thead>
                            <tr>
                                <th>Stage</th>
                                <th class="num">Invocations</th>
                                <th class="num">Tokens</th>
                                <th class="num">Cost</th>
                                <th class="num">Avg Duration</th>
                            </tr>
                        </thead>
                        <tbody>
            `;
            for (const s of data.by_stage) {
                html += `
                    <tr>
                        <td>${this.escapeHtml(s.stage)}</td>
                        <td class="num">${s.invocations}</td>
                        <td class="num">${this.formatNumber(s.tokens || 0)}</td>
                        <td class="num cost-value">${this.formatCost(s.cost || 0)}</td>
                        <td class="num">${(s.avg_duration_seconds || 0).toFixed(1)}s</td>
                    </tr>
                `;
            }
            html += '</tbody></table></div>';
        }

        // By Mission table
        if (data.by_mission && data.by_mission.length > 0) {
            html += `
                <div class="costs-section">
                    <h3 class="costs-section-title">By Mission</h3>
                    <table class="costs-table">
                        <thead>
                            <tr>
                                <th>Mission</th>
                                <th class="num">Invocations</th>
                                <th class="num">Tokens</th>
                                <th class="num">Cost</th>
                            </tr>
                        </thead>
                        <tbody>
            `;
            for (const m of data.by_mission) {
                html += `
                    <tr>
                        <td>${this.escapeHtml(m.mission)}</td>
                        <td class="num">${m.invocations}</td>
                        <td class="num">${this.formatNumber(m.tokens || 0)}</td>
                        <td class="num cost-value">${this.formatCost(m.cost || 0)}</td>
                    </tr>
                `;
            }
            html += '</tbody></table></div>';
        }

        // By Run table
        if (data.by_run && data.by_run.length > 0) {
            html += `
                <div class="costs-section">
                    <h3 class="costs-section-title">By Run</h3>
                    <table class="costs-table">
                        <thead>
                            <tr>
                                <th>Run ID</th>
                                <th>Mission</th>
                                <th class="num">Invocations</th>
                                <th class="num">Tokens</th>
                                <th class="num">Cost</th>
                            </tr>
                        </thead>
                        <tbody>
            `;
            for (const r of data.by_run) {
                html += `
                    <tr>
                        <td>${this.escapeHtml(r.run_id)}</td>
                        <td>${this.escapeHtml(r.mission || '')}</td>
                        <td class="num">${r.invocations}</td>
                        <td class="num">${this.formatNumber(r.tokens || 0)}</td>
                        <td class="num cost-value">${this.formatCost(r.cost || 0)}</td>
                    </tr>
                `;
            }
            html += '</tbody></table></div>';
        }

        this.container.innerHTML = html;
    },

    calcCacheRatio(models) {
        let totalInput = 0;
        let totalCacheRead = 0;
        for (const m of models) {
            const tu = m.token_usage || {};
            totalInput += (tu.input_tokens || 0) + (tu.cache_creation_input_tokens || 0) + (tu.cache_read_input_tokens || 0);
            totalCacheRead += (tu.cache_read_input_tokens || 0);
        }
        if (totalInput === 0) return 'N/A';
        return (totalCacheRead / totalInput * 100).toFixed(1) + '%';
    },

    formatCost(cost) {
        if (cost === 0) return '$0.00';
        if (cost < 0.01) return '$' + cost.toFixed(4);
        return '$' + cost.toFixed(2);
    },

    formatNumber(n) {
        if (n >= 1000000) return (n / 1000000).toFixed(1) + 'M';
        if (n >= 1000) return (n / 1000).toFixed(1) + 'K';
        return n.toString();
    },

    escapeHtml(text) {
        if (!text) return '';
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }
};
