// Cytoscape graph visualization for Orbit dashboard — PCB-inspired theme

const Graph = {
    cy: null,
    tooltip: null,
    selectedNode: null,

    // Initialize the graph
    init(container) {
        this.cy = cytoscape({
            container: container,
            style: this.getStyles(),
            layout: { name: 'preset' },
            minZoom: 0.3,
            maxZoom: 2,
            wheelSensitivity: 0.3,
        });

        // Create tooltip element
        this.tooltip = document.createElement('div');
        this.tooltip.className = 'cy-tooltip';
        this.tooltip.style.display = 'none';
        document.body.appendChild(this.tooltip);

        // Set up event handlers
        this.setupEvents();

        // HTML labels overlaid on nodes (tooltip-style rich content)
        if (typeof this.cy.nodeHtmlLabel === 'function') {
            this.initHtmlLabels();
        } else {
            console.warn('cytoscape-node-html-label extension not loaded — falling back to built-in labels');
            this.cy.style().selector('node').style('label', 'data(label)').update();
        }

        return this;
    },

    // Get Cytoscape stylesheet — PCB trace & IC package styling
    getStyles() {
        return [
            // Base node styles — labels rendered as HTML overlays
            {
                selector: 'node',
                style: {
                    'label': '',
                    'shadow-blur': 12,
                    'shadow-color': 'rgba(0, 0, 0, 0.5)',
                    'shadow-opacity': 1,
                    'shadow-offset-x': 0,
                    'shadow-offset-y': 4,
                }
            },

            // Mission nodes — blue border (compound parent)
            // Extra padding gives room for orbits_to loop-back lines on the right
            {
                selector: 'node[type="mission"]',
                style: {
                    'shape': 'rectangle',
                    'background-color': '#0d1e2e',
                    'border-width': 1,
                    'border-color': '#58a6ff',
                    'padding': '50px',
                }
            },

            // Module nodes — purple border (compound parent)
            {
                selector: 'node[type="module"]',
                style: {
                    'shape': 'rectangle',
                    'background-color': '#1a142e',
                    'border-width': 1,
                    'border-color': '#9a6eff',
                    'padding': '30px',
                }
            },

            // Stage nodes — green compound container
            {
                selector: 'node[type="stage"]',
                style: {
                    'shape': 'rectangle',
                    'background-color': '#132e23',
                    'border-width': 1,
                    'border-color': '#5cb870',
                    'padding': '24px',
                    'min-width': '95px',
                    'min-height': '50px',
                }
            },

            // Component nodes — dark green IC (nested inside stages)
            {
                selector: 'node[type="component"]',
                style: {
                    'shape': 'rectangle',
                    'width': '100px',
                    'height': '30px',
                    'background-color': '#0f2a18',
                    'border-width': 1,
                    'border-color': '#3fb950',
                }
            },

            // Standalone component nodes (not nested in a stage) — larger
            {
                selector: 'node[type="component"]:orphan',
                style: {
                    'width': '120px',
                    'height': '38px',
                }
            },

            // Sensor nodes — floating rectangle
            {
                selector: 'node[type="sensor"]',
                style: {
                    'shape': 'rectangle',
                    'width': '200px',
                    'height': '60px',
                    'background-color': '#2a1510',
                    'border-width': 1,
                    'border-color': '#f78166',
                    'padding': '14px',
                }
            },

            // Status: pending — dim border
            {
                selector: 'node[status="pending"]',
                style: {
                    'border-color': '#6e7a6a',
                }
            },

            // Status: running — amber glow LED
            {
                selector: 'node[status="running"]',
                style: {
                    'border-color': '#ffa726',
                    'border-width': 3,
                    'shadow-blur': 15,
                    'shadow-color': '#ffa726',
                    'shadow-opacity': 0.7,
                    'shadow-offset-x': 0,
                    'shadow-offset-y': 0,
                }
            },

            // Status: success — green LED
            {
                selector: 'node[status="success"]',
                style: {
                    'border-color': '#4caf50',
                }
            },

            // Status: failed — red LED
            {
                selector: 'node[status="failed"]',
                style: {
                    'border-color': '#f44336',
                    'shadow-blur': 10,
                    'shadow-color': '#f44336',
                    'shadow-opacity': 0.5,
                    'shadow-offset-x': 0,
                    'shadow-offset-y': 0,
                }
            },

            // Status: offline — faded
            {
                selector: 'node[status="offline"]',
                style: {
                    'border-color': '#3a4a3a',
                    'opacity': 0.5,
                }
            },

            // Status: defined — subtle
            {
                selector: 'node[status="defined"]',
                style: {
                    'border-color': '#4a5a4a',
                }
            },

            // Selected state — copper highlight
            {
                selector: 'node:selected',
                style: {
                    'border-width': 3,
                    'border-color': '#ffc46b',
                    'overlay-color': '#e8a44a',
                    'overlay-padding': 4,
                    'overlay-opacity': 0.15,
                }
            },

            // ── Edge styles: PCB traces ──

            // Base edge — copper dim, orthogonal taxi routing
            {
                selector: 'edge',
                style: {
                    'width': 2,
                    'line-color': '#5a4a30',
                    'target-arrow-color': '#5a4a30',
                    'target-arrow-shape': 'triangle-tee',
                    'arrow-scale': 0.7,
                    'curve-style': 'taxi',
                    'taxi-direction': 'downward',
                    'taxi-turn': '50%',
                }
            },

            // depends_on — solid copper trace, green tint
            {
                selector: 'edge[type="depends_on"]',
                style: {
                    'line-color': '#7a8a70',
                    'target-arrow-color': '#7a8a70',
                    'width': 2.5,
                }
            },

            // orbits_to — bright copper, dashed feedback loop arcing right.
            // Uses bezier curve that always arcs 90px right of the source→target line,
            // so it never overlaps with the straight sequential arrows.
            {
                selector: 'edge[type="orbits_to"]',
                style: {
                    'line-color': '#e8a44a',
                    'target-arrow-color': '#e8a44a',
                    'line-style': 'dashed',
                    'curve-style': 'unbundled-bezier',
                    'control-point-distances': [90],
                    'control-point-weights': [0.5],
                }
            },

            // triggers — warm accent, bezier for cross-compound edges
            {
                selector: 'edge[type="triggers"]',
                style: {
                    'line-color': '#ff7b5a',
                    'target-arrow-color': '#ff7b5a',
                    'line-style': 'dashed',
                    'width': 1.5,
                    'curve-style': 'bezier',
                }
            },

            // uses_module — purple dotted, bezier for cross-compound edges
            {
                selector: 'edge[type="uses_module"]',
                style: {
                    'line-color': '#9a6eff',
                    'target-arrow-color': '#9a6eff',
                    'line-style': 'dotted',
                    'curve-style': 'bezier',
                }
            },

            // delivers — bright copper, solid, with label, bezier for cross-compound edges
            {
                selector: 'edge[type="delivers"]',
                style: {
                    'line-color': '#e8a44a',
                    'target-arrow-color': '#e8a44a',
                    'width': 3,
                    'curve-style': 'bezier',
                    'label': 'data(label)',
                    'font-size': '8px',
                    'font-family': "'JetBrains Mono', monospace",
                    'color': '#8b6d3f',
                    'text-outline-width': 1,
                    'text-outline-color': '#0a1a14',
                    'text-rotation': 'autorotate',
                    'text-margin-y': -8,
                }
            },

            // Active trace animation class
            {
                selector: 'edge.active-trace',
                style: {
                    'line-color': '#e8a44a',
                    'target-arrow-color': '#e8a44a',
                    'line-style': 'dashed',
                    'line-dash-pattern': [4, 8],
                }
            },
        ];
    },

    // Set up event handlers
    setupEvents() {
        // Node click
        this.cy.on('tap', 'node', (evt) => {
            const node = evt.target;
            this.selectedNode = node;
            if (typeof Panels !== 'undefined') {
                Panels.showNodeDetail(node.data());
            }
        });

        // Background click - deselect
        this.cy.on('tap', (evt) => {
            if (evt.target === this.cy) {
                this.selectedNode = null;
                if (typeof Panels !== 'undefined') {
                    Panels.hide();
                }
            }
        });

        // Hover for tooltips (sensors)
        this.cy.on('mouseover', 'node[type="sensor"]', (evt) => {
            const node = evt.target;
            const data = node.data();
            this.showTooltip(evt.originalEvent, data);
        });

        this.cy.on('mouseout', 'node[type="sensor"]', () => {
            this.hideTooltip();
        });

        // Update tooltip position on mousemove
        this.cy.on('mousemove', 'node[type="sensor"]', (evt) => {
            this.moveTooltip(evt.originalEvent);
        });
    },

    // Register HTML label overlays — tooltip-style rich content per node type
    initHtmlLabels() {
        try {
        this.cy.nodeHtmlLabel([
            // Compound parents: mission — top-positioned
            {
                query: 'node[type="mission"]',
                halign: 'center',
                valign: 'top',
                halignBox: 'center',
                valignBox: 'top',
                cssClass: 'cy-node-label-mission',
                tpl: (data) =>
                    '<div class="node-type">MISSION</div>' +
                    '<div class="node-title">' + (data.name || '') + '</div>'
            },
            // Compound parents: module — top-positioned
            {
                query: 'node[type="module"]',
                halign: 'center',
                valign: 'top',
                halignBox: 'center',
                valignBox: 'top',
                cssClass: 'cy-node-label-module',
                tpl: (data) =>
                    '<div class="node-type">MODULE</div>' +
                    '<div class="node-title">' + (data.name || '') + '</div>'
            },
            // Compound parents: stage — top-positioned
            {
                query: 'node[type="stage"]',
                halign: 'center',
                valign: 'top',
                halignBox: 'center',
                valignBox: 'top',
                cssClass: 'cy-node-label-stage',
                tpl: (data) =>
                    '<div class="node-type">STAGE</div>' +
                    '<div class="node-title">' + (data.name || '') + '</div>'
            },
            // Leaf: component — centered
            {
                query: 'node[type="component"]',
                halign: 'center',
                valign: 'center',
                halignBox: 'center',
                valignBox: 'center',
                cssClass: 'cy-node-label-component',
                tpl: (data) =>
                    '<div class="node-title">' + (data.name || '') + '</div>'
            },
            // Leaf: sensor — centered
            {
                query: 'node[type="sensor"]',
                halign: 'center',
                valign: 'center',
                halignBox: 'center',
                valignBox: 'center',
                cssClass: 'cy-node-label-sensor',
                tpl: (data) => {
                    const patterns = data.patterns || [];
                    const target = data.target || data.name || '';
                    let html = '<div class="node-type">SENSOR</div>';
                    html += '<div class="node-title">' + target + '</div>';
                    if (patterns.length > 0) {
                        html += '<div class="node-content">' +
                            patterns.map(p => p.replace(/^components\//, '')).join('<br>') +
                            '</div>';
                    }
                    return html;
                }
            },
        ]);

        // Extension handles zoom scaling via CSS transforms automatically
        } catch (err) {
            console.error('nodeHtmlLabel init failed:', err);
            this.cy.style().selector('node').style('label', 'data(label)').update();
        }
    },

    // Show tooltip
    showTooltip(evt, data) {
        const patterns = data.data?.patterns || [];
        let html = `
            <div class="tooltip-type">${data.type}</div>
            <div class="tooltip-title">${data.data?.target || data.label}</div>
        `;
        if (patterns.length > 0) {
            html += `<div class="tooltip-patterns">${patterns.join('<br>')}</div>`;
        }
        this.tooltip.innerHTML = html;
        this.tooltip.style.display = 'block';
        this.moveTooltip(evt);
    },

    // Move tooltip
    moveTooltip(evt) {
        const x = evt.clientX + 12;
        const y = evt.clientY + 12;
        this.tooltip.style.left = x + 'px';
        this.tooltip.style.top = y + 'px';
    },

    // Hide tooltip
    hideTooltip() {
        this.tooltip.style.display = 'none';
    },

    // Update graph with new data
    update(graphData) {
        if (!graphData || !graphData.nodes) {
            console.warn('No graph data to update');
            return;
        }

        console.log('Updating graph with', graphData.nodes.length, 'nodes');

        // Convert to Cytoscape format (nodes are already sorted: parents before children)
        const elements = this.convertToElements(graphData);

        // Track if we need to run layout
        let needsLayout = false;

        // Batch update
        this.cy.batch(() => {
            // Get current elements
            const existingIds = new Set();
            this.cy.nodes().forEach(n => existingIds.add(n.id()));
            this.cy.edges().forEach(e => existingIds.add(e.id()));

            // Track new element IDs
            const newIds = new Set();
            elements.nodes.forEach(n => newIds.add(n.data.id));
            elements.edges.forEach(e => newIds.add(e.data.id));

            // Remove elements that no longer exist
            this.cy.elements().forEach(el => {
                if (!newIds.has(el.id())) {
                    el.remove();
                }
            });

            // Separate nodes into 3 depth levels for correct compound ordering
            const allParentIds = new Set(elements.nodes.filter(n => n.data.parent).map(n => n.data.parent));
            const depth0 = []; // no parent (missions, standalone components, sensors)
            const depth1 = []; // parent exists, parent has no parent (stages)
            const depth2 = []; // parent exists, parent also has a parent (nested components)

            for (const node of elements.nodes) {
                if (!node.data.parent) {
                    depth0.push(node);
                } else if (allParentIds.has(node.data.parent)) {
                    // Parent is itself a parent → check if parent has a parent
                    const parentNode = elements.nodes.find(n => n.data.id === node.data.parent);
                    if (parentNode && parentNode.data.parent) {
                        depth2.push(node);
                    } else {
                        depth1.push(node);
                    }
                } else {
                    depth1.push(node);
                }
            }

            // Add/update nodes in depth order: 0, 1, 2
            for (const bucket of [depth0, depth1, depth2]) {
                for (const node of bucket) {
                    const existing = this.cy.getElementById(node.data.id);
                    if (existing.length > 0) {
                        existing.data(node.data);
                    } else {
                        this.cy.add(node);
                        needsLayout = true;
                    }
                }
            }

            // Finally add edges
            for (const edge of elements.edges) {
                const existing = this.cy.getElementById(edge.data.id);
                if (existing.length === 0) {
                    // Only add edge if both source and target exist
                    const source = this.cy.getElementById(edge.data.source);
                    const target = this.cy.getElementById(edge.data.target);
                    if (source.length > 0 && target.length > 0) {
                        this.cy.add(edge);
                    }
                }
            }
        });

        // Run layout if we added new nodes
        if (needsLayout && this.cy.nodes().length > 0) {
            this.runLayout();
        }

        // Update running animation
        this.updateRunningAnimation();
    },

    // Convert API data to Cytoscape elements
    convertToElements(graphData) {
        // Sort nodes by nesting depth: depth 0 (missions, standalone components, sensors),
        // depth 1 (stages inside missions), depth 2 (components inside stages)
        const parentSet = new Set(graphData.nodes.filter(n => n.parent).map(n => n.parent));

        const getDepth = (node) => {
            if (!node.parent) return 0;
            if (!parentSet.has(node.parent)) return 1;
            // parent also has a parent → grandchild
            const parentNode = graphData.nodes.find(n => n.id === node.parent);
            if (parentNode && parentNode.parent) return 2;
            return 1;
        };

        const sortedNodes = [...graphData.nodes].sort((a, b) => {
            return getDepth(a) - getDepth(b);
        });

        const typePrefixes = {
            'mission': 'MISSION',
            'module': 'MODULE',
            'stage': 'STAGE',
        };

        const nodes = sortedNodes.map(n => {
            let label;
            const prefix = typePrefixes[n.type];
            if (prefix) {
                label = `${prefix}: ${n.label}`;
            } else if (n.type === 'sensor') {
                // Build multi-line label: "SENSORS" header + watch patterns
                const patterns = n.data?.patterns || [];
                label = 'SENSORS';
                if (patterns.length > 0) {
                    label += '\n' + patterns.join('\n');
                }
            } else {
                label = n.label;
            }
            // Spread n.data first so that explicit fields (type, label, etc.) win
            return {
                data: {
                    ...n.data,
                    id: n.id,
                    name: n.label,
                    label: label,
                    type: n.type,
                    status: n.status,
                    parent: n.parent,
                }
            };
        });

        const edges = graphData.edges.map(e => ({
            data: {
                id: e.id,
                source: e.source,
                target: e.target,
                type: e.type,
                label: e.data?.label || '',
            }
        }));

        return { nodes, edges };
    },

    // Run the layout algorithm
    runLayout() {
        console.log('Running layout on', this.cy.nodes().length, 'nodes');

        const allNodes = this.cy.nodes();
        const sensors = this.cy.nodes('[type="sensor"]');

        console.log('Total nodes:', allNodes.length, 'Sensors:', sensors.length);

        // Include all nodes (including sensors) in dagre layout.
        // Sensors connect via trigger edges and participate naturally.
        if (allNodes.length > 0) {
            try {
                const elements = allNodes.union(this.cy.edges());

                elements.layout({
                    name: 'dagre',
                    rankDir: 'TB',
                    align: 'UL',
                    nodeSep: 40,
                    rankSep: 60,
                    edgeSep: 20,
                    padding: 30,
                    animate: false,
                    fit: false,
                    spacingFactor: 1.2,
                }).run();

                console.log('Dagre layout completed');
            } catch (err) {
                console.error('Dagre layout error:', err);
                allNodes.layout({
                    name: 'grid',
                    padding: 30,
                    animate: false,
                }).run();
            }
        }

        // Post-layout: vertically stack stages within each mission
        this.stackMissionStages();

        // Fallback for sensors without edges (no trigger connections)
        if (sensors.length > 0 && typeof Layout !== 'undefined') {
            Layout.positionSensors(this.cy, sensors);
        }

        // Fit to viewport with padding
        this.cy.fit(50);
        console.log('Layout completed');
    },

    // Post-layout: vertically stack stages within each mission compound node
    stackMissionStages() {
        const missions = this.cy.nodes('[type="mission"]');
        missions.forEach(mission => {
            const stages = mission.children('[type="stage"]');
            if (stages.length <= 1) return;

            // Sort by current Y position (preserves dagre's dependency ordering),
            // then by X as tiebreaker for stages at the same rank
            const sorted = stages.sort((a, b) => {
                const dy = a.position('y') - b.position('y');
                if (Math.abs(dy) > 5) return dy;
                return a.position('x') - b.position('x');
            });

            // Use the average X as the vertical column center
            let centerX = 0;
            sorted.forEach(s => { centerX += s.position('x'); });
            centerX = centerX / sorted.length;

            // Stack vertically with consistent spacing
            const spacing = 120;
            const startY = sorted[0].position('y');

            sorted.forEach((stage, i) => {
                stage.position({ x: centerX, y: startY + (i * spacing) });
            });
        });
    },

    // Update running animation
    updateRunningAnimation() {
        // Add/remove running class for CSS animation
        this.cy.nodes('[status="running"]').addClass('running');
        this.cy.nodes('[status!="running"]').removeClass('running');
    },

    // Animate edges connected to running nodes (marching-ants copper trace)
    animateEdges() {
        // Performance gate: skip for large graphs
        if (this.cy.nodes().length >= 100) return;

        const runningNodes = this.cy.nodes('[status="running"]');

        // Remove active-trace from all edges first
        this.cy.edges('.active-trace').removeClass('active-trace');

        if (runningNodes.length === 0) return;

        // Find edges connected to running nodes
        const activeEdges = runningNodes.connectedEdges();
        activeEdges.addClass('active-trace');

        // Animate dash offset for marching-ants effect
        activeEdges.forEach(edge => {
            if (edge._animating) return;
            edge._animating = true;

            const animate = () => {
                if (!edge.hasClass('active-trace')) {
                    edge._animating = false;
                    return;
                }
                edge.animate({
                    style: { 'line-dash-offset': -24 },
                    duration: 800,
                    easing: 'linear',
                    complete: () => {
                        edge.style('line-dash-offset', 0);
                        if (edge.hasClass('active-trace')) {
                            animate();
                        } else {
                            edge._animating = false;
                        }
                    }
                });
            };
            animate();
        });
    },

    // Center on a specific node
    centerOn(nodeId) {
        const node = this.cy.getElementById(nodeId);
        if (node.length > 0) {
            this.cy.animate({
                center: { eles: node },
                zoom: 1,
                duration: 300
            });
        }
    },

    // Reset view
    resetView() {
        this.cy.fit(30);
    }
};
