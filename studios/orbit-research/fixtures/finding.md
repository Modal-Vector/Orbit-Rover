# T-001-A: ReAct Pattern Analysis

## Source

Yao et al. (2022). "ReAct: Synergizing Reasoning and Acting in Language Models."
arXiv:2210.03629.

## Key Findings

- **Core loop**: Thought → Action → Observation, repeated until task completion
- **Reasoning trace**: Each step includes explicit reasoning before action selection
- **Grounding**: Actions produce observations that ground subsequent reasoning
- **Termination**: Loop exits when the model generates a "Finish" action with answer
- **Error recovery**: No built-in retry — failed actions produce error observations
  that the model must reason about

## Cross-References

- Related to T-002 (graph-based): ReAct is a strict sequential loop, unlike
  LangGraph's branching state machine
- Relevant to T-003 (context management): ReAct accumulates full history, creating
  context pressure in long tasks

## Open Questions

- How does ReAct performance degrade as the reasoning trace grows?
- Can the pattern be extended with checkpointing for crash recovery?
