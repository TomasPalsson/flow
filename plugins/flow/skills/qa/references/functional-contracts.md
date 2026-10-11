# Functional Contracts (API, CLI, jobs, webhooks)

For changes that have no page to click: HTTP endpoints, CLI commands, queue consumers, scheduled jobs, webhooks. The Contract Tester agent loads this in Wave 2. Use the repository's own commands and clients (curl, the CLI itself, the job runner's invoke command). Do not build a new harness.

## Contract map

Record one row per contract: the source (route, command, handler), the setup, the exact probe, the expectation, and the outcome (pass, fail, blocked, not run, inconclusive, not applicable with a reason).

| Contract | What to observe |
|----------|-----------------|
| Success path | The returned value and the final effect (row written, file produced, message delivered), not only that the call was accepted |
| Invalid or missing input | The declared rejection, the right status or exit code, and no state change |
| Auth | Valid identity, missing or invalid identity, wrong owner or role; the denied case leaves no effect |
| CLI process | Exit code, stdout and stderr read separately, and the files or state left behind |
| State transitions | Initial, intermediate, completed and failed states, and which moves are allowed |
| Timeout and cancellation | The deadline, the partial state it leaves, and whether owned work stops |
| Retry | The attempts and backoff the repository promises, the terminal state, and no unbounded retry |
| Duplicates | The same request or event twice: how many durable effects result under the documented guarantee |
| Concurrency | Two competing operations in both completion orders; the final invariant holds |
| Partial failure | Interrupt after one effect, restart or replay, then check the final state and any duplicates |

## Reading the result

- A 2xx (or a queued job id) is acceptance, not completion. Probe acceptance, enqueue, processing, retry or dead-letter, and the final effect as separate steps, and check the effect itself.
- Do not assume exactly-once delivery. Test against the guarantee the repository documents (at-least-once with idempotent handlers, for example) and report a duplicate effect only when it breaks that guarantee.
- For a CLI, one passing exit code is not enough: compare stdout, stderr, and the side effects with what the help text or docs promise.
- An expected rejection or an injected failure that behaves as designed is a pass.
- A required service that cannot start (database, queue, emulator) blocks coverage of the contracts that need it. Record those contracts under Not Tested as blocked, with the reason, never as passed.

## Safety

Use synthetic data and test credentials. Run against local or staging targets only; a probe that sends mail, charges a card, or writes to a shared production resource is listed under Not Tested rather than run. Follow the browser-safety rule in [`verification.md`](../../shared/verification.md#browser-safety) for any page you open along the way.

Credit: adapted from garrytan/gstack qa/sections/system-functional.md @ 5b9b837 (MIT).
