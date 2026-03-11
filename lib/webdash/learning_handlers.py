"""Learning system API handlers for Orbit Rover web dashboard.

Reads JSONL from .orbit/learning/ (already JSON, no YAML conversion needed).
"""

import json
import os


def handle_learning_summary(state_dir):
    """Handle /api/learning/summary — counts."""
    learning_dir = os.path.join(state_dir, 'learning')
    counts = {
        'feedback': _count_entries(os.path.join(learning_dir, 'feedback')),
        'insights': _count_entries(os.path.join(learning_dir, 'insights')),
        'decisions': _count_entries(os.path.join(learning_dir, 'decisions')),
    }
    return 200, counts


def handle_learning_feedback(state_dir):
    """Handle /api/learning/feedback."""
    return 200, _read_all_jsonl(os.path.join(state_dir, 'learning', 'feedback'))


def handle_learning_insights(state_dir):
    """Handle /api/learning/insights."""
    return 200, _read_all_jsonl(os.path.join(state_dir, 'learning', 'insights'))


def handle_learning_decisions(state_dir):
    """Handle /api/learning/decisions."""
    return 200, _read_all_jsonl(os.path.join(state_dir, 'learning', 'decisions'))


def _count_entries(directory):
    """Count total JSONL entries across all files in a directory."""
    if not os.path.isdir(directory):
        return 0
    count = 0
    for fname in os.listdir(directory):
        if fname.endswith('.jsonl'):
            try:
                with open(os.path.join(directory, fname), 'r') as f:
                    for line in f:
                        if line.strip():
                            count += 1
            except OSError:
                continue
    return count


def _read_all_jsonl(directory):
    """Read all JSONL entries from all files in a directory."""
    if not os.path.isdir(directory):
        return []
    entries = []
    for fname in sorted(os.listdir(directory)):
        if not fname.endswith('.jsonl'):
            continue
        try:
            with open(os.path.join(directory, fname), 'r') as f:
                for line in f:
                    line = line.strip()
                    if line:
                        try:
                            entries.append(json.loads(line))
                        except json.JSONDecodeError:
                            continue
        except OSError:
            continue
    return entries
