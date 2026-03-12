# orbit-sentinel

Intelligence monitoring studio. Monitors a watchlist of sources and produces
periodic intelligence summaries.

## Specialist Subagents

Use these via the Agent tool when working in this studio.

| Agent | When to spawn | What it returns |
|-------|---------------|-----------------|
| `signal-correlator` | After generating findings — pass it the findings directory | Cross-source pattern detection, trend identification across current and prior runs |
| `threat-enricher` | When encountering CVEs or security advisories — pass it the CVE ID or advisory text | CVSS scoring, ATT&CK technique mapping, known exploit context, and remediation guidance |
