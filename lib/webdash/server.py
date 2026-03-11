#!/usr/bin/env python3
"""HTTP server for Orbit Rover web dashboard.

Uses only Python stdlib (http.server, json, os, etc.).
Reads JSON config files (pre-converted from YAML by the bash entry point).
"""

import argparse
import json
import os
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler
from socketserver import ThreadingMixIn
from urllib.parse import urlparse, parse_qs

from graph_builder import GraphBuilder
from api_handlers import (
    handle_graph, handle_missions, handle_components,
    handle_runs, handle_sensors, handle_flight_rules,
    handle_telemetry, handle_costs, handle_modules,
    SSEHandler,
)
from learning_handlers import (
    handle_learning_summary, handle_learning_feedback,
    handle_learning_insights, handle_learning_decisions,
)


class ThreadingHTTPServer(ThreadingMixIn, HTTPServer):
    """Multi-threaded HTTP server for concurrent SSE + regular requests."""
    daemon_threads = True
    allow_reuse_address = True


class DashboardHandler(BaseHTTPRequestHandler):
    """Request handler for the Orbit web dashboard."""

    # Shared state set by server setup
    builder = None
    static_dir = None
    state_dir = None
    yq_path = None
    cache_dir = None
    project_dir = None

    def log_message(self, format, *args):
        """Suppress default request logging."""
        pass

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path.rstrip('/')
        query = parse_qs(parsed.query)

        # Route
        if path == '' or path == '/':
            self._serve_file('index.html', 'text/html')
        elif path.startswith('/static/'):
            rel_path = path[len('/static/'):]
            self._serve_static(rel_path)
        elif path.startswith('/api/'):
            self._handle_api(path, query)
        else:
            self._send_error(404, 'Not found')

    def _handle_api(self, path, query):
        parts = [p for p in path.split('/') if p]  # ['api', 'graph', ...]

        if len(parts) < 2:
            self._send_error(404, 'Unknown API endpoint')
            return

        endpoint = parts[1]

        if endpoint == 'events':
            self._handle_sse()
            return

        # Dispatch to handlers
        status = 200
        data = None

        if endpoint == 'graph':
            status, data = handle_graph(
                self.builder, self.yq_path, self.cache_dir, self.project_dir)
        elif endpoint == 'missions':
            status, data = handle_missions(self.builder, parts)
        elif endpoint == 'components':
            status, data = handle_components(self.builder, parts)
        elif endpoint == 'runs':
            status, data = handle_runs(self.builder, parts, query)
        elif endpoint == 'sensors':
            status, data = handle_sensors(self.builder)
        elif endpoint == 'flight-rules':
            status, data = handle_flight_rules(self.builder)
        elif endpoint == 'telemetry':
            status, data = handle_telemetry(self.builder)
        elif endpoint == 'costs':
            status, data = handle_costs(self.builder)
        elif endpoint == 'modules':
            status, data = handle_modules(self.builder)
        elif endpoint == 'learning':
            if len(parts) > 2:
                sub = parts[2]
                if sub == 'summary':
                    status, data = handle_learning_summary(self.state_dir)
                elif sub == 'feedback':
                    status, data = handle_learning_feedback(self.state_dir)
                elif sub == 'insights':
                    status, data = handle_learning_insights(self.state_dir)
                elif sub == 'decisions':
                    status, data = handle_learning_decisions(self.state_dir)
                else:
                    status, data = 404, {'error': 'unknown learning endpoint'}
            else:
                status, data = handle_learning_summary(self.state_dir)
        else:
            status, data = 404, {'error': 'unknown endpoint'}

        self._send_json(status, data)

    def _handle_sse(self):
        """Handle SSE connection for live updates."""
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.send_header('Cache-Control', 'no-cache')
        self.send_header('Connection', 'keep-alive')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()

        handler = SSEHandler(
            self.builder, self.yq_path, self.cache_dir, self.project_dir)
        handler.generate(self.wfile)

    def _send_json(self, status, data):
        body = json.dumps(data, separators=(',', ':')).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Cache-Control', 'no-cache, no-store')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_error(self, status, message):
        self._send_json(status, {'error': message})

    def _serve_file(self, filename, content_type):
        filepath = os.path.join(self.static_dir, filename)
        if not os.path.isfile(filepath):
            self._send_error(404, 'Not found')
            return
        try:
            with open(filepath, 'rb') as f:
                body = f.read()
            self.send_response(200)
            self.send_header('Content-Type', content_type)
            self.send_header('Content-Length', str(len(body)))
            self.send_header('Cache-Control', 'no-cache')
            self.end_headers()
            self.wfile.write(body)
        except OSError:
            self._send_error(500, 'Internal server error')

    def _serve_static(self, rel_path):
        # Prevent directory traversal
        safe_path = os.path.normpath(rel_path)
        if safe_path.startswith('..') or safe_path.startswith('/'):
            self._send_error(403, 'Forbidden')
            return

        filepath = os.path.join(self.static_dir, safe_path)
        if not os.path.isfile(filepath):
            self._send_error(404, 'Not found')
            return

        # Content type mapping
        ext = os.path.splitext(filepath)[1].lower()
        content_types = {
            '.html': 'text/html',
            '.css': 'text/css',
            '.js': 'application/javascript',
            '.json': 'application/json',
            '.png': 'image/png',
            '.svg': 'image/svg+xml',
            '.woff2': 'font/woff2',
            '.woff': 'font/woff',
        }
        content_type = content_types.get(ext, 'application/octet-stream')

        try:
            with open(filepath, 'rb') as f:
                body = f.read()
            self.send_response(200)
            self.send_header('Content-Type', content_type)
            self.send_header('Content-Length', str(len(body)))
            # Cache vendor JS for 1 hour, other static for no-cache
            if '/vendor/' in safe_path:
                self.send_header('Cache-Control', 'public, max-age=3600')
            else:
                self.send_header('Cache-Control', 'no-cache')
            self.end_headers()
            self.wfile.write(body)
        except OSError:
            self._send_error(500, 'Internal server error')


def main():
    parser = argparse.ArgumentParser(description='Orbit Rover Web Dashboard')
    parser.add_argument('--port', type=int, default=8067)
    parser.add_argument('--state-dir', required=True)
    parser.add_argument('--project-dir', required=True)
    parser.add_argument('--cache-dir', required=True)
    parser.add_argument('--yq-path', default='')
    args = parser.parse_args()

    # Resolve paths
    state_dir = os.path.abspath(args.state_dir)
    project_dir = os.path.abspath(args.project_dir)
    cache_dir = os.path.abspath(args.cache_dir)
    script_dir = os.path.dirname(os.path.abspath(__file__))
    static_dir = os.path.join(script_dir, 'static')

    # Create builder
    builder = GraphBuilder(project_dir, state_dir, cache_dir)

    # Configure handler
    DashboardHandler.builder = builder
    DashboardHandler.static_dir = static_dir
    DashboardHandler.state_dir = state_dir
    DashboardHandler.yq_path = args.yq_path or None
    DashboardHandler.cache_dir = cache_dir
    DashboardHandler.project_dir = project_dir

    server = ThreadingHTTPServer(('0.0.0.0', args.port), DashboardHandler)

    print('Orbit Rover dashboard: http://localhost:%d' % args.port)
    print('Press Ctrl+C to stop')

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print('\nShutting down...')
        server.shutdown()


if __name__ == '__main__':
    main()
