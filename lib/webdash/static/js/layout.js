// Custom layout helpers for the Orbit dashboard

const Layout = {
    // Position sensor nodes relative to the graph.
    // Sensors now participate in dagre layout via their trigger edges,
    // so this is only called as a fallback when sensors have no edges.
    positionSensors(cy, sensors) {
        if (sensors.length === 0) return;

        // Check if sensors already have positions from dagre (via trigger edges)
        const positioned = sensors.filter(s => {
            const pos = s.position();
            return pos.x !== 0 || pos.y !== 0;
        });

        // If dagre already positioned them, nothing to do
        if (positioned.length === sensors.length) return;

        // Fallback: position unpositioned sensors below the main graph
        const others = cy.nodes('[type!="sensor"]');
        let bbox;
        if (others.length > 0) {
            bbox = others.boundingBox();
        } else {
            bbox = { x1: 0, x2: 400, y1: 0, y2: 200 };
        }

        const sensorY = bbox.y2 + 100;
        const startX = bbox.x1;
        const spacing = 120;

        const unpositioned = sensors.filter(s => {
            const pos = s.position();
            return pos.x === 0 && pos.y === 0;
        });

        unpositioned.forEach((sensor, i) => {
            sensor.position({
                x: startX + (i * spacing) + 60,
                y: sensorY
            });
        });
    },

    // Calculate optimal positions for a set of nodes in a grid
    gridLayout(nodes, options = {}) {
        const cols = options.cols || Math.ceil(Math.sqrt(nodes.length));
        const spacing = options.spacing || 150;
        const startX = options.startX || 0;
        const startY = options.startY || 0;

        nodes.forEach((node, i) => {
            const col = i % cols;
            const row = Math.floor(i / cols);
            node.position({
                x: startX + (col * spacing),
                y: startY + (row * spacing)
            });
        });
    },

    // Position nodes in a horizontal line
    horizontalLine(nodes, options = {}) {
        const spacing = options.spacing || 120;
        const startX = options.startX || 0;
        const y = options.y || 0;

        nodes.forEach((node, i) => {
            node.position({
                x: startX + (i * spacing),
                y: y
            });
        });
    },

    // Position nodes in a vertical line
    verticalLine(nodes, options = {}) {
        const spacing = options.spacing || 80;
        const x = options.x || 0;
        const startY = options.startY || 0;

        nodes.forEach((node, i) => {
            node.position({
                x: x,
                y: startY + (i * spacing)
            });
        });
    }
};
