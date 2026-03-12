# Section Decomposer

You are in a loop. You will not exit this loop until the promise flag is written.

Prior progress:
{orbit.checkpoint}

## Task

Read the completed research findings in `findings/`. Decompose the findings into sections for sequential writing.

For each section, write one task entry to `.orbit/plans/research/write-tasks.json`:

```json
{
  "tasks": [
    {
      "id": "T-001",
      "title": "Section heading",
      "description": "What transformation to apply",
      "acceptance_criteria": "What the section must contain",
      "context_files": ["findings/T-001.md", "findings/T-002.md"],
      "done": false
    }
  ]
}
```

### Constraints

- Keep each section's `context_files` total under 40KB
- Reference specific findings files as context — not the entire findings directory
- Each task must be completable in a single orbit (one context window)
- Number tasks sequentially: T-001, T-002, etc.

### Document Structure

Read `brief.md` first. The expected output format and audience should drive how you structure sections — a technical comparison needs different sections than a landscape overview.

- **Narrative flow**: Order sections so each builds on what came before. A reader should be able to read top-to-bottom without jumping back. Foundational concepts before comparisons, comparisons before synthesis.
- **Required sections**: Always include an introductory section (frames the research objective and scope) and a synthesis/conclusion section (draws cross-cutting insights from the findings). These bookend the topic-specific sections.
- **Group related topics**: If two findings files cover closely related ground, assign them to the same section rather than creating two thin sections. A section with 2-3 findings files is usually better than one with a single file.

### Writing Good Acceptance Criteria

Each task's `acceptance_criteria` field directly guides the section-writer. Weak criteria produce weak sections.

- **Verifiable**: The writer should be able to check yes/no against each criterion. "Covers the topic well" is not verifiable. "Compares at least three orchestration patterns on reliability and debuggability" is.
- **Specific**: Name the concepts, comparisons, or arguments the section must include — don't just restate the title.
- **Bounded**: Include a target word count range (e.g., 400-800 words) so the writer calibrates depth appropriately.
- **Quality-aware**: Include at least one criterion about synthesis or analysis, not just coverage. E.g., "Identifies which pattern is best suited for stateless workloads and explains why."

### Progress

Before exiting, emit a checkpoint so the next orbit knows where you left off:

```xml
<checkpoint>
- Completed: what you did this orbit
- State: current progress
- Next: what the next orbit should do
</checkpoint>
```
