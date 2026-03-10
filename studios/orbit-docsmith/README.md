# orbit-docsmith — Document Transformation Studio

Transforms a source document into a polished structured document using Orbit Rover's
ralph loop pattern.

## Usage

```bash
# Initialise Orbit in this directory
orbit init

# Copy your source document to the project root

# Launch the transform mission
orbit launch transform

# Monitor progress
orbit status transform
```

## How It Works

1. **Decompose stage**: The `section-decomposer` reads your source document and
   creates a task list in `.orbit/plans/docsmith/tasks.json`, one task per section.

2. **Write stage**: The `section-writer` processes one section per orbit, writing
   output to `output/`. It loops until all tasks are marked done.

## Configuration

Edit `orbit.yaml` to change defaults:
- `model`: Change from `sonnet` to `opus` for higher quality output
- `timeout`: Increase for larger sections
- Component `orbits.max`: Adjust the ceiling for the writer loop

## Requirements

- bash 4+
- jq
- An AI adapter: `claude-code` (default) or `opencode`
