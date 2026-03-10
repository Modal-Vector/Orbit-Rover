# Fieldops Risk Registry

Risk classification for all operational tools in the fieldops studio.

## Tool Classification

| Tool | Classification | Requires Approval | Risk Description |
|------|----------------|-------------------|------------------|
| read-logs | available | no | Read-only log access |
| check-health | available | no | Non-destructive health check |
| notify-operator | available | no | Write-only notification |
| restart-service | restricted | yes | Data loss possible during restart |
| apply-config-patch | restricted | yes | System impact from config changes |

## Risk Levels

- **available**: Tool can be used freely by any component. No approval needed.
- **restricted**: Tool requires explicit assignment to a component and auth key validation. Changes are logged and operator is notified.

## Approval Flow

1. Component requests restricted tool via `<tool_request>` tag
2. Operator reviews request: `orbit tools pending`
3. Operator grants: `orbit tools grant <request-id>`
4. Auth key is generated and stored in `.orbit/tool-auth/{component}.json`
5. Tool validates auth key via `_auth-check.sh` before execution

## Escalation

If a remediation requires tools not in the assigned set:
1. Remediator emits `<tool_request>` with justification
2. Loop continues with available tools
3. Operator grants access via CLI when available
4. Next orbit picks up the newly available tool
