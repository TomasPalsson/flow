# Feature plan (fixture — valid Discovered section)

## Behavior Inventory

| Behavior | Slice | Verified by |
|---|---|---|
| Thing one happens | Slice 1 | `test_one` |
| Thing two happens | Slice 2 | `test_two` |

## Slice 1 — First thing

- **Files**: src/one.py

### Slice 1 — RED

red

### Slice 1 — GREEN

green

### Slice 1 — REFACTOR

refactor

## Slice 2 — Second thing

- **Files**: src/two.py
- **Depends-on**: Slice 1

### Slice 2 — RED

red

### Slice 2 — GREEN

green

### Slice 2 — REFACTOR

refactor

## Discovered

- Found an edge case in validation — discovered in Slice 1 — defer
- Found a shared helper opportunity — discovered in Slice 2 — fold into Slice 1

Fenced decoy that must not be parsed as a new heading or a stray bullet:

```text
## Slice 9 — decoy
- bogus bullet — discovered in Slice 9 — defer
```

## Gate Phases

1. Run `check-all` after every slice.
