# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Orbit Rover, please report it
privately through [GitHub Security Advisories](https://github.com/Modal-Vector/Orbit-Rover/security/advisories/new).

**Do not open a public issue for security vulnerabilities.**

We will acknowledge your report within 48 hours and aim to provide a fix or
mitigation within 7 days for confirmed vulnerabilities.

## Threat Model

Orbit Rover is a local CLI tool that executes AI agents as subprocesses. It does
not run a network server (except the optional web dashboard bound to localhost).

**What Rover trusts:**
- YAML config files (`orbit.yaml`, component/mission definitions) are treated as
  code. Values flow into shell commands and template variables. Rover does not
  sandbox or validate these — if you can write a config file, you can execute
  arbitrary commands. This is by design: configs live in the repo and go through
  the same review process as code.
- The `.orbit/` state directory is written by Rover and read back on subsequent
  orbits. Rover trusts its own state files. Protect `.orbit/` with filesystem
  permissions as you would any working directory.
- Tool auth keys are HMAC-derived from a project secret and stored as plaintext
  in `.orbit/`. They govern which tools an agent can request, not access to
  external systems.

**What Rover does not protect against:**
- A compromised agent writing malicious content into deliverables, checkpoints,
  or learning files that a subsequent orbit interprets unsafely. Rover provides
  no output sanitisation — the agent is trusted to the extent its adapter policy
  allows.
- Credential leakage if users place secrets in config values, prompt templates,
  or deliverable files that end up in `.orbit/` logs or state. Keep secrets in
  environment variables, not in Orbit configs.

**What we consider in-scope vulnerabilities:**
- Bugs where Rover itself introduces an injection vector (e.g., unsafe `eval` on
  agent output, unquoted variable expansion in shell commands)
- Path traversal or symlink-following in file operations that Rover controls
- Auth key generation flaws that make keys predictable or forgeable
- Web dashboard (localhost) serving content that enables XSS or CSRF

## Supported Versions

| Version | Supported |
|---------|-----------|
| 0.1.x   | Yes       |
