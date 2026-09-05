# Feature plan (fixture — dependency cycle)

## Behavior Inventory

| Behavior | Slice | Verified by |
|---|---|---|
| Thing happens | Slice 1 | `test_thing` |

## Slice 1 — First thing

- **Files**: src/one.py
- **Depends-on**: Slice 2

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

## Gate Phases

1. Run `check-all` after every slice.
