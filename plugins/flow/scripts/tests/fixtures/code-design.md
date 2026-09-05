# Code design (fixture, U3 scripts-flow)

## Contract for this slice — Slice 1

`POST /login` accepts `{email, password}`. On success it returns `200` with
a `Set-Cookie: session=<token>` header. On failure it returns `401` with no
cookie. `token` is opaque and stored server-side keyed by session id.

## Contract for this slice — Slice 2

`POST /logout` reads the `session` cookie, deletes the server-side session
record, and returns `204` with a `Set-Cookie: session=; Max-Age=0` header
to clear the client cookie. Missing/invalid cookie also returns `204`
(idempotent).

## Contract for this slice — Slice 3

The session middleware rejects any request whose session record's
`last_seen` is older than `SESSION_TIMEOUT_SECONDS` (default 1800) with a
`401`, and otherwise refreshes `last_seen` to now.
