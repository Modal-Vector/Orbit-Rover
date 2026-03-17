# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Orbit Rover, please report it
privately through [GitHub Security Advisories](https://github.com/Modal-Vector/Orbit-Rover/security/advisories/new).

**Do not open a public issue for security vulnerabilities.**

We will acknowledge your report within 48 hours and aim to provide a fix or
mitigation within 7 days for confirmed vulnerabilities.

## Scope

Orbit Rover is a local CLI tool — it does not run a network server (except the
optional web dashboard bound to localhost). Security concerns most relevant to
this project include:

- Command injection through config values or template variables
- Unsafe file operations (symlink attacks, path traversal)
- Credential exposure through logs or state files
- Insecure handling of tool auth keys

## Supported Versions

| Version | Supported |
|---------|-----------|
| 0.1.x   | Yes       |
