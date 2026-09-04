# Feature plan (fixture, intentionally broken)

## Behavior Inventory

| Behavior | Slice | Verified by |
|---|---|---|

## Slice 1 — Login

- **Files**: src/auth/login.ts
- **Depends-on**: Slice 2

### Slice 1 — RED

Write a failing test for `login(email, password)`.

### Slice 1 — GREEN

Implement `login`.

## Slice 2 — Logout

- **Files**: src/auth/logout.ts

### Slice 2 — RED

Write a failing test for `logout(sessionToken)`.

### Slice 2 — GREEN

Implement `logout`.

### Slice 2 — REFACTOR

No changes needed; code is already minimal.

## Gate Phases

1. Run `check-all` after every slice.
