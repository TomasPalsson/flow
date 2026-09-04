# Decision-Ladder Worksheet

Copy this into your design doc. The rule is **measured, not assumed**: you may only descend a rung after a *concrete eval* (≈20 representative cases is enough to see 30%→80% effect sizes) shows the rung above is insufficient. "I think it won't work" is not a passing gate.

```
TASK: ____________________________________________________________

RUNG 1 — Single optimized LLM call (+ retrieval + in-context examples)
  Eval result: ____ / 20 passed.   Failing because: __________________
  [ ] Proven insufficient by eval → descend.   Else STOP HERE.

RUNG 2 — Workflow (predefined code paths, LLM at fixed steps)
  Operative question: can step COUNT and SEQUENCE be fixed before run? [ ] yes → workflow fits
  Which pattern? [ ] chaining  [ ] routing(classifier acc ___% ≥90?)  [ ] sectioning  [ ] voting(N=__)  [ ] evaluator-optimizer
  Pulled the free lever first? [ ] parallel tool calls within one call
  Eval result: ____ / 20.   [ ] Proven insufficient → descend.   Else STOP HERE.

RUNG 3 — Single autonomous agent (gather → act → verify → repeat)
  Stopping conditions set?  [ ] max-iterations ___  [ ] token budget ___  [ ] terminal tool states (SUCCESS/FAILED/PARTIAL)
  Context plan?             [ ] caching  [ ] tool-result clearing  [ ] compaction  [ ] external memory
  Tool surface < 20?        [ ] yes  / dynamic loading plan: __________
  Verification?             [ ] evaluator / approval gate before irreversible actions
  Eval result: ____ / 20.   [ ] Proven insufficient FOR THIS TASK → descend.   Else STOP HERE.

RUNG 4 — Multi-agent (orchestrator-workers).  ALL must be TRUE:
  [ ] breadth-first with genuinely INDEPENDENT parallel threads
  [ ] value ≥ ~15x a chat answer (run token_cost_calculator.py --multiagent)
  [ ] subtasks need LITTLE shared context
  [ ] work overflows one 200K window
  Is this CODING?  [ ] yes → STOP, stay single-agent (shared mutable state; coordination dominates)
  Orchestrator prompt has scaling rules? [ ] 1 / 2–4 / 10+ subagents by task type
  Each subagent delegation has? [ ] objective [ ] output format [ ] tool/source guidance [ ] boundaries
```

**Estimate the cost of each candidate rung before committing:**
```
python scripts/token_cost_calculator.py --model <m> --input <n> --output <n> \
    --calls-per-day <n> --cache-hit <0..1> [--multiagent]
```

**Record the decision and WHY** (so the next engineer doesn't re-litigate it):
```
CHOSE RUNG: ___   BECAUSE (eval evidence): ____________________________
REJECTED RUNG ___ BECAUSE: ____________________________________________
ESTIMATED COST: $______/month   KEY TOKEN LEVERS APPLIED: ______________
```
