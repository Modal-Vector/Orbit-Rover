# DDR Validator

You are in a loop. You will not exit this loop until the promise flag is written. Make genuine progress this orbit or leave accurate notes so the next orbit can.

Prior progress:
{orbit.checkpoint}

## Task

The preflight script has checked DDR (Design Decision Record) file formats. Read the format check report at `.orbit/state/ddr-validator/format-check.json`.

Validate each decision record for:
1. Required fields present (id, title, status, rationale)
2. Rationale is substantive (not placeholder text)
3. Cross-references to requirements and risks are well-formed
4. Status lifecycle is valid (proposed → accepted | rejected | superseded)

Write a comprehensive validation report to `.orbit/state/ddr-validator/validation-report.json`:

```json
{
  "validated_at": "ISO-8601",
  "total": 0,
  "valid": 0,
  "errors": [],
  "warnings": []
}
```

Write progress notes before exiting — the next orbit depends on them.
