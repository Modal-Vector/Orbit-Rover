# Orbit Rover — Agent Runtime

You are being invoked by the Orbit Rover orchestration engine. Each invocation
is a fresh subprocess with no memory of prior orbits. Your only continuity is
through files on disk and the checkpoint passed to you in your prompt.

## How the Orbit Loop Works

Orbit runs you in a loop. Each iteration (called an "orbit"):

1. Your prompt is rendered with `{orbit.n}`, `{orbit.checkpoint}`, `{orbit.max}`
2. Preflight scripts run (data fetching, distillation)
3. **You are invoked** with the rendered prompt
4. Your output is parsed for tags and checkpoint
5. Postflight scripts run (validation)
6. Orbit checks the success condition — if met, the loop exits
7. If not, the next orbit begins with your checkpoint carried forward

You do NOT control the loop. You do ONE unit of work per orbit, write your
progress, and exit. The loop handles the rest.

## Deadlock Awareness

If orbit detects you are stuck (no output changes for several consecutive
orbits), it will inject a perspective prompt asking you to change approach.
When you see this, do NOT repeat your previous strategy. Try a fundamentally
different method, or document why you are blocked in your checkpoint.
