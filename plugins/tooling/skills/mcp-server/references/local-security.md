# Local server security

For a server that reads files, runs commands or holds secrets on the user's machine. Tool results
flow into the chat transcript, so anything returned is visible to the user and to log exports.

- **Contain every path.** Resolve each path parameter, then require the result to sit under an
  allowed root. Reject `../../etc/passwd` after resolution, not before.
- **No shell strings.** Use `execFile` or array argv; never `exec()` or `shell=True` with
  model-supplied text.
- **Split reads from writes** and set the annotations honestly (see `tool-design.md`):
  `readOnlyHint` on proven read tools, `destructiveHint` on delete and overwrite tools.
- **Cap sizes:** file reads, directory listings and search results, and say so when truncating.
- **Secrets:** read from environment or the OS keychain, never log them, never return them in a
  tool result, never write them to a plaintext file.

Checklist before shipping:

- [ ] Every path parameter goes through the containment check
- [ ] No `exec()` / `shell=True`
- [ ] Write and delete tools are separate from read tools, annotations set
- [ ] Size caps on reads, listings and search
- [ ] Secrets never logged or returned
- [ ] Tried with `../../etc/passwd`, `; touch /tmp/mcp-injected` (the file must not appear) and a 10 GB file

Credit: adapted from anthropics/claude-plugins-official plugins/mcp-server-dev/skills/build-mcpb/references/local-security.md @ a9fd216 (Apache-2.0).
