# Feature plan (fixture — misplaced Discovered section and a bad bullet)

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

## Discovered

- Found an edge case — discovered in Slice 1 — defer
- Found an unrelated widget — discovered in Slice 9 — fold into Slice 1

## Slice 2 — Second thing

- **Files**: src/two.py

### Slice 2 — RED

red

### Slice 2 — GREEN

green

### Slice 2 — REFACTOR

refactor

## Gate Phases

1. Run `check-all` after every slice.
