// API helper functions for the Orbit web dashboard

const API = {
    pollInterval: 1000,
    pollTimer: null,
    onUpdate: null,
    lastError: null,
    eventSource: null,
    useSSE: true,

    // Fetch the complete graph data
    async fetchGraph() {
        try {
            const response = await fetch('/api/graph');
            if (!response.ok) {
                throw new Error(`HTTP ${response.status}`);
            }
            this.lastError = null;
            return await response.json();
        } catch (err) {
            this.lastError = err;
            throw err;
        }
    },

    // Fetch mission list
    async fetchMissions() {
        const response = await fetch('/api/missions');
        if (!response.ok) {
            throw new Error(`HTTP ${response.status}`);
        }
        return await response.json();
    },

    // Fetch mission detail
    async fetchMissionDetail(name) {
        const response = await fetch(`/api/missions/${encodeURIComponent(name)}`);
        if (!response.ok) {
            throw new Error(`HTTP ${response.status}`);
        }
        return await response.json();
    },

    // Fetch modules list
    async fetchModules() {
        const response = await fetch('/api/modules');
        if (!response.ok) {
            throw new Error(`HTTP ${response.status}`);
        }
        return await response.json();
    },

    // Fetch components list
    async fetchComponents() {
        const response = await fetch('/api/components');
        if (!response.ok) {
            throw new Error(`HTTP ${response.status}`);
        }
        return await response.json();
    },

    // Fetch component detail
    async fetchComponentDetail(name) {
        const response = await fetch(`/api/components/${encodeURIComponent(name)}`);
        if (!response.ok) {
            throw new Error(`HTTP ${response.status}`);
        }
        return await response.json();
    },

    // Fetch sensors list
    async fetchSensors() {
        const response = await fetch('/api/sensors');
        if (!response.ok) {
            throw new Error(`HTTP ${response.status}`);
        }
        return await response.json();
    },

    // Fetch costs breakdown
    async fetchCosts() {
        const response = await fetch('/api/costs');
        if (!response.ok) {
            throw new Error(`HTTP ${response.status}`);
        }
        return await response.json();
    },

    // Fetch runs list, optionally filtered by mission name
    async fetchRuns(missionName) {
        let url = '/api/runs';
        if (missionName) {
            url += `?mission=${encodeURIComponent(missionName)}`;
        }
        const response = await fetch(url);
        if (!response.ok) {
            throw new Error(`HTTP ${response.status}`);
        }
        return await response.json();
    },

    // Fetch run detail
    async fetchRunDetail(runID) {
        const response = await fetch(`/api/runs/${encodeURIComponent(runID)}`);
        if (!response.ok) {
            throw new Error(`HTTP ${response.status}`);
        }
        return await response.json();
    },

    // Start polling — tries SSE first, falls back to HTTP polling
    startPolling(callback) {
        this.onUpdate = callback;

        if (this.useSSE && typeof EventSource !== 'undefined') {
            this.startSSE();
        } else {
            this.poll();
        }
    },

    // Start Server-Sent Events connection
    startSSE() {
        if (this.eventSource) {
            this.eventSource.close();
        }

        this.eventSource = new EventSource('/api/events');

        this.eventSource.onmessage = (event) => {
            try {
                const data = JSON.parse(event.data);
                if (this.onUpdate) {
                    this.onUpdate(data, null);
                }
                this.updateConnectionStatus(true);
            } catch (err) {
                console.error('SSE parse error:', err);
            }
        };

        this.eventSource.onerror = () => {
            this.updateConnectionStatus(false);
            // EventSource auto-reconnects; no manual fallback needed
            // unless the browser doesn't support it
        };

        this.eventSource.onopen = () => {
            this.updateConnectionStatus(true);
        };
    },

    // Stop polling / SSE
    stopPolling() {
        if (this.pollTimer) {
            clearTimeout(this.pollTimer);
            this.pollTimer = null;
        }
        if (this.eventSource) {
            this.eventSource.close();
            this.eventSource = null;
        }
    },

    // Internal poll function (fallback)
    async poll() {
        try {
            const data = await this.fetchGraph();
            if (this.onUpdate) {
                this.onUpdate(data, null);
            }
            this.updateConnectionStatus(true);
        } catch (err) {
            if (this.onUpdate) {
                this.onUpdate(null, err);
            }
            this.updateConnectionStatus(false);
        }

        // Schedule next poll
        this.pollTimer = setTimeout(() => this.poll(), this.pollInterval);
    },

    // Update connection indicator
    updateConnectionStatus(connected) {
        const el = document.getElementById('connection');
        if (el) {
            if (connected) {
                el.classList.remove('disconnected');
                el.querySelector('.connection-text').textContent = 'connected';
            } else {
                el.classList.add('disconnected');
                el.querySelector('.connection-text').textContent = 'disconnected';
            }
        }
    }
};
