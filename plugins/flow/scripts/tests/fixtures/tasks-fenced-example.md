# Tasks — Fenced example
Spec: spec.md · Base: 4f2a91c · Route: dispatch · Test: `pytest -q`

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 | given / when / then | T001 | t1 |

## Phase 1 — Real work
Goal: a fenced example must never be parsed as a task.
Independent test: `pytest -q`
- [ ] T001 Real task — files: src/a.py — verify: `pytest -q`

Example of a bad line, quoted for the docs:

```
## Gates
- [ ] T999 fake task with no verify
- [~] T998 dropped with no reason
```

## Gates
- [ ] G001 clean — verify: `flow check`
