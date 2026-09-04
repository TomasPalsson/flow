# Feature plan (fixture)

## Behavior Inventory

| Behavior | Slice | Verified by |
|---|---|---|
| User can log in with a valid password | Slice 1 | `test_login_valid` |
| User sees an error on a wrong password | Slice 1 | `test_login_invalid` |
| User can log out | Slice 2 | `test_logout` |

## Slice 1 — Login

- **Files**: src/auth/login.ts, src/auth/login.test.ts

### Slice 1 — RED

Write a failing test for `login(email, password)` returning a session token.

### Slice 1 — GREEN

Implement `login` against the in-memory user store.

### Slice 1 — REFACTOR

Extract password hashing into `src/auth/hash.ts`.

## Slice 2 — Logout

- **Files**: src/auth/logout.ts
- **Depends-on**: Slice 1

### Slice 2 — RED

Write a failing test for `logout(sessionToken)` invalidating the session.

Here is a fenced block that must not be parsed as real headings, including
a decoy slice heading that a naive line-scanner would mistake for a new
top-level slice:

```text
## Slice 9 — decoy
### Slice 9 — RED
### Slice 9 — GREEN
### Slice 9 — REFACTOR
```

### Slice 2 — GREEN

Implement `logout` clearing the session from the store.

### Slice 2 — REFACTOR

No changes needed; code is already minimal.

## Gate Phases

1. Run `check-all` after every slice.
2. Full sweep before merge.
