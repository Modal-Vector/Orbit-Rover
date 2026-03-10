# Fieldops Tool Index

Tools available to the operations studio components.

| Tool | File | Classification | Description |
|------|------|----------------|-------------|
| read-logs | tools/read-logs.sh | available | Read specified log files |
| check-health | tools/check-health.sh | available | Check service health endpoints |
| notify-operator | tools/notify-operator.sh | available | Send operator notifications |
| restart-service | tools/restart-service.sh | restricted | Restart a system service |
| apply-config-patch | tools/apply-config-patch.sh | restricted | Apply configuration changes |

## Auth Gate

Restricted tools require a valid `ORBIT_TOOL_AUTH_KEY`. The `_auth-check.sh` script
validates the key against `.orbit/tool-auth/{component}.json` before allowing execution.

## Adding Tools

1. Create the tool script in `tools/`
2. Add it to this INDEX.md
3. Update `RISK-REGISTRY.md` with classification
4. If restricted, assign it to the component in the component YAML
