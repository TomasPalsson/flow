# Feature plan (fixture — two-wave dependency graph)

## Behavior Inventory

| Behavior | Slice | Verified by |
|---|---|---|
| Thing one happens | Slice 1 | `test_one` |
| Thing two happens | Slice 2 | `test_two` |
| Thing three happens | Slice 3 | `test_three` |

## Slice 1 — First thing

- **Files**: src/a.py

### Slice 1 — RED

red

### Slice 1 — GREEN

green

### Slice 1 — REFACTOR

refactor

## Slice 2 — Second thing

- **Files**: src/b.py
- **Depends-on**: Slice 1

### Slice 2 — RED

red

### Slice 2 — GREEN

green

### Slice 2 — REFACTOR

refactor

## Slice 3 — Third thing

- **Files**: src/c.py
- **Depends-on**: Slice 1

### Slice 3 — RED

red

### Slice 3 — GREEN

green

### Slice 3 — REFACTOR

refactor

## Gate Phases

1. Run `check-all` after every slice.
