# Feature plan (fixture, U3 scripts-flow)

## Behavior Inventory

| Behavior | Slice | Verified by |
|---|---|---|
| User can log in | Slice 1 | test_login.py::test_login_success |
| User can log out | Slice 2 | test_logout.py::test_logout_success |
| Session expires after timeout | Slice 3 | test_session.py::test_expiry |

## Slice 1 — Login flow

- **Files**: src/auth/login.py, src/auth/session.py

### Slice 1 — RED

Write a failing test for the login endpoint returning a session cookie.

### Slice 1 — GREEN

Implement the login endpoint against the in-memory user store.

### Slice 1 — REFACTOR

Extract cookie signing into a helper.

## Slice 2 — Logout flow

- **Files**: src/auth/logout.py
- **Depends-on**: Slice 1

### Slice 2 — RED

Write a failing test for the logout endpoint invalidating the session.

### Slice 2 — GREEN

Implement the logout endpoint clearing the session cookie.

Here is a fenced block that must not be parsed as real headings, including
a decoy slice heading that a naive line-scanner would mistake for a new
top-level slice:

```text
## Slice 9 — decoy
### Slice 9 — RED
### Slice 9 — GREEN
### Slice 9 — REFACTOR
```

### Slice 2 — REFACTOR

No changes needed; the logout handler is already minimal.

## Slice 3 — Session expiry

- **Files**: src/auth/timeout.py, src/auth/session_expiry.py
- **Depends-on**: Slice 1, Slice 2

### Slice 3 — RED

Write a failing test asserting a session is rejected after the configured timeout.

### Slice 3 — GREEN

Implement the timeout check in the session middleware.

### Slice 3 — REFACTOR

Move the timeout constant into config.

## Gate Phases

1. Run `check-all` after every slice.
2. Full sweep before merge.
