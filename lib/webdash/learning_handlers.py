"""Learning system API handlers for Orbit Rover web dashboard.

Reads JSONL from .orbit/learning/ (already JSON, no YAML conversion needed).
"""

import json
import os


def handle_learning_summary(state_dir):
    """Handle /api/learning/summary — counts."""
    learning_dir = os.path.join(state_dir, 'learning')
    project_dir = os.path.dirname(state_dir)
    counts = {
        'feedback': _count_feedback_entries(os.path.join(project_dir, 'components')),
        'insights': _count_entries(os.path.join(learning_dir, 'insights')),
        'decisions': _count_entries(os.path.join(learning_dir, 'decisions')),
    }
    return 200, counts


def handle_learning_feedback(state_dir):
    """Handle /api/learning/feedback."""
    project_dir = os.path.dirname(state_dir)
    return 200, _read_feedback_jsonl(os.path.join(project_dir, 'components'))


def handle_learning_insights(state_dir):
    """Handle /api/learning/insights."""
    return 200, _read_all_jsonl(os.path.join(state_dir, 'learning', 'insights'))


def handle_learning_decisions(state_dir):
    """Handle /api/learning/decisions."""
    return 200, _read_all_jsonl(os.path.join(state_dir, 'learning', 'decisions'))


def _count_feedback_entries(components_dir):
    """Count total feedback JSONL entries across component directories."""
    if not os.path.isdir(components_dir):
        return 0
    count = 0
    for comp_name in os.listdir(components_dir):
        comp_dir = os.path.join(components_dir, comp_name)
        if not os.path.isdir(comp_dir):
            continue
        for fname in os.listdir(comp_dir):
            if fname.endswith('.feedback.jsonl'):
                try:
                    with open(os.path.join(comp_dir, fname), 'r') as f:
                        for line in f:
                            if line.strip():
                                count += 1
                except OSError:
                    continue
    return count


def _read_feedback_jsonl(components_dir):
    """Read all feedback JSONL entries from component directories."""
    if not os.path.isdir(components_dir):
        return []
    entries = []
    for comp_name in sorted(os.listdir(components_dir)):
        comp_dir = os.path.join(components_dir, comp_name)
        if not os.path.isdir(comp_dir):
            continue
        for fname in sorted(os.listdir(comp_dir)):
            if not fname.endswith('.feedback.jsonl'):
                continue
            try:
                with open(os.path.join(comp_dir, fname), 'r') as f:
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
