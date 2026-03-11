// Main entry point for the Orbit web dashboard

document.addEventListener('DOMContentLoaded', () => {
    // Initialize components
    const graphContainer = document.getElementById('graph-container');
    Graph.init(graphContainer);
    Panels.init();
    Runs.init();
    Costs.init();

    // View toggle tabs
    const tabGraph = document.getElementById('tab-graph');
    const tabRuns = document.getElementById('tab-runs');
    const tabCosts = document.getElementById('tab-costs');

    if (tabGraph) {
        tabGraph.addEventListener('click', () => {
            Runs.hide();
            Costs.hide();
        });
    }
    if (tabRuns) {
        tabRuns.addEventListener('click', () => {
            Costs.hide();
            Runs.show();
        });
    }
    if (tabCosts) {
        tabCosts.addEventListener('click', () => {
            Costs.show();
        });
    }

    // Event log state
    const EventLog = {
        entries: [],
        maxEntries: 100,
        container: document.getElementById('event-log-content'),
        countEl: document.getElementById('event-count'),
        logEl: document.getElementById('event-log'),

        add(message) {
            const now = new Date();
            const time = now.toLocaleTimeString('en-US', { hour12: false });
            this.entries.unshift({ time, message });
            if (this.entries.length > this.maxEntries) {
                this.entries.pop();
            }
            this.render();
        },

        render() {
            if (!this.container) return;
            this.container.innerHTML = this.entries.map(e =>
                `<div class="event-entry">
                    <span class="event-time">${e.time}</span>
                    <span class="event-message">${e.message}</span>
                </div>`
            ).join('');
            if (this.countEl) {
                this.countEl.textContent = this.entries.length;
            }
        },

        toggle() {
            if (this.logEl) {
                this.logEl.classList.toggle('expanded');
            }
        }
    };

    // Set up event log toggle
    const toggleBtn = document.getElementById('event-log-toggle');
    if (toggleBtn) {
        toggleBtn.addEventListener('click', () => EventLog.toggle());
    }

    // State diffing for event detection
    let previousStatuses = {};

    function detectTransitions(graphData) {
        if (!graphData || !graphData.nodes) return;

        const currentStatuses = {};
        for (const node of graphData.nodes) {
            currentStatuses[node.id] = node.status || 'defined';
        }

        // Compare with previous state
        for (const [id, status] of Object.entries(currentStatuses)) {
            const prev = previousStatuses[id];
            if (prev && prev !== status) {
                const label = id.split(':').slice(1).join(':') || id;
                EventLog.add(`${label}: ${prev} → ${status}`);
            }
        }

        previousStatuses = currentStatuses;
    }

    // Update metrics display
    function updateMetrics(metrics) {
        if (!metrics) return;

        const els = {
            missions: document.getElementById('metric-missions'),
            components: document.getElementById('metric-components'),
            invocations: document.getElementById('metric-invocations'),
            tokens: document.getElementById('metric-tokens'),
        };

        if (els.missions) els.missions.textContent = metrics.active_missions || 0;
        if (els.components) els.components.textContent = metrics.active_components || 0;
        if (els.invocations) els.invocations.textContent = formatNumber(metrics.total_invocations || 0);
        if (els.tokens) els.tokens.textContent = formatNumber(metrics.total_tokens || 0);
    }

    // Format large numbers
    function formatNumber(n) {
        if (n >= 1000000) {
            return (n / 1000000).toFixed(1) + 'M';
        }
        if (n >= 1000) {
            return (n / 1000).toFixed(1) + 'K';
        }
        return n.toString();
    }

    // Handle graph updates
    function onGraphUpdate(data, err) {
        if (err) {
            console.error('Graph update error:', err);
            return;
        }

        if (data) {
            detectTransitions(data);
            Graph.update(data);
            Graph.animateEdges();
            updateMetrics(data.metrics);
        }
    }

    // Start polling (SSE with fallback)
    API.startPolling(onGraphUpdate);

    // Initial fetch
    API.fetchGraph()
        .then(data => {
            console.log('Graph data received:', data.nodes.length, 'nodes,', data.edges.length, 'edges');
            Graph.update(data);
            Graph.animateEdges();
            updateMetrics(data.metrics);

            // Initialize status tracking
            for (const node of data.nodes) {
                previousStatuses[node.id] = node.status || 'defined';
            }

            console.log('Cytoscape nodes:', Graph.cy.nodes().length);
        })
        .catch(err => {
            console.error('Initial fetch failed:', err);
        });

    // Keyboard shortcuts
    document.addEventListener('keydown', (e) => {
        if (isInputFocused()) return;
        if (e.ctrlKey || e.metaKey) return;

        switch (e.key) {
            case 'r':
                Graph.resetView();
                break;
            case 'f':
                Graph.resetView();
                break;
            case 'e':
                EventLog.toggle();
                break;
            case 'h':
                if (Runs.active) {
                    Runs.hide();
                } else {
                    Runs.show();
                }
                break;
            case 'c':
                if (Costs.active) {
                    Costs.hide();
                    // Show graph
                    if (Runs.container) Runs.container.classList.add('hidden');
                    const gc = document.getElementById('graph-container');
                    if (gc) gc.classList.remove('hidden');
                    document.querySelectorAll('.view-tab').forEach(t => t.classList.remove('active'));
                    const gt = document.getElementById('tab-graph');
                    if (gt) gt.classList.add('active');
                } else {
                    Costs.show();
                }
                break;
            case 'i':
                // Toggle detail panel
                if (Panels.panel && !Panels.panel.classList.contains('hidden')) {
                    Panels.hide();
                }
                break;
        }
    });

    function isInputFocused() {
        const active = document.activeElement;
        return active && (
            active.tagName === 'INPUT' ||
            active.tagName === 'TEXTAREA' ||
            active.isContentEditable
        );
    }
});
