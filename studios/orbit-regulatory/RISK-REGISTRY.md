# Regulatory Studio Risk Registry

Risk classification for the TGA SaMD regulatory documentation process.

## Process Risks

| Risk Area | Classification | Impact | Mitigation |
|-----------|----------------|--------|------------|
| Requirement gaps | high | Incomplete regulatory submission | Traceability matrix verification |
| Risk control gaps | high | Unmitigated safety risks | Risk monitor continuous checking |
| SOUP vulnerabilities | medium | Security/safety impact | SOUP assessment and monitoring |
| Traceability breaks | high | Failed regulatory audit | Automated trace generation |
| Document staleness | medium | Outdated regulatory evidence | Reactive decision-capture mission |
| Classification drift | high | Incorrect TGA classification | Regulatory analyst review |

## Document Types and Regulatory Mapping

| Document | TGA Guidance | IEC 62304 | IEC 14971 |
|----------|-------------|-----------|-----------|
| SRS (Software Requirements) | Essential Principles | §5.2 | — |
| SDS (Software Design) | Essential Principles | §5.3 | — |
| Risk Management Plan | TGA risk framework | — | §4-7 |
| SOUP Assessment | TGA SOUP guidance | §8 | — |
| V&V Plan | TGA verification | §5.5-5.7 | — |
| Traceability Matrix | TGA traceability | §5.6 | §3.4 |

## Approval Flow

All regulatory documents require qualified-person review via manual gate before finalisation.
The `generate-docs` mission includes a 120-hour review gate with default reject.
