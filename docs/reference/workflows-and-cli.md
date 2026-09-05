# Saved workflows

Discovered from the plugin's `workflows/` at session start and registered as `flow:<name>`; invoked with `Workflow({ name: 'flow:<name>' })`.

## flow:build-slices

export const meta = {
  name: 'build-slices',
  description: 'Implement plan slices with brief, developer, review-package, adversarial review, and a bounded fix ladder',
  whenToUse: 'Use in Workflow mode to implement one or more slices from a frozen plan end to end',
  phases: [
    { title: 'Brief', detail: 'slice-brief extracts the slice section (and design contract) into a brief file' },
    { title: 'Implement', detail: 'a developer agent implements the slice from the brief only' },
    { title: 'Review', detail: 'review-package builds the diff; two adversary lenses check it' },
    { title: 'Fix', detail: 'bounded fix ladder on fatal/significant findings, then a recorded ruling' },
  ],
}

## flow:plan-review

export const meta = {
  name: 'plan-review',
  description: 'Attack a spec and plan with adversarial lenses, then adjudicate the findings into decisions',
  whenToUse: 'Use before implementation starts to pressure-test a frozen spec and plan',
  phases: [
    { title: 'Attack', detail: 'independent lenses attack the spec and plan' },
    { title: 'Adjudicate', detail: 'one agent merges findings into decisions' },
  ],
}

## flow:research-sweep

export const meta = {
  name: 'research-sweep',
  description: 'Decompose a question into angles, research and check each, then synthesize a cited report',
  whenToUse: 'Use for open research questions needing verified, cited claims',
  phases: [
    { title: 'Angles', detail: 'decompose the question into distinct angles' },
    { title: 'Search', detail: 'one researcher agent per angle gathers claims' },
    { title: 'Check', detail: 'one checker agent per angle refetches load-bearing claims' },
    { title: 'Synthesize', detail: 'one agent writes the cited report' },
  ],
}

## flow:review-diff

export const meta = {
  name: 'review-diff',
  description: 'Package a diff, review it through independent lenses, and re-score every finding blind',
  whenToUse: 'Use to review a range of commits before merge with independently re-scored findings',
  phases: [
    { title: 'Package', detail: 'review-package builds the diff for base..head' },
    { title: 'Find', detail: 'independent lenses read the diff for real issues' },
    { title: 'Score', detail: 'each unique finding is re-scored 0-100 against fixed anchors' },
  ],
}

# flow CLI

```

flow — deterministic project harness CLI

Usage:
  flow <command> [options]

Commands:
  doctor [--json] [--verbose]                      Diagnose the ~/.claude deployment
                                                     (--verbose names each check as it runs)
  init [--stack auto|node|python|rust|go] [--dry-run] [--force]
                                                     Scaffold REVIEW.md, PROGRESS.md,
                                                     CLAUDE.md, CI gate, lint thresholds
  install [--dry-run] [--dotfiles <path>] [--marketplace <path>] [--force]
                                                     Deploy the harness on this machine
                                                     (idempotent); ends by running doctor
  check [--fix]                                     Run project quality gates (check-all)
  skills-lint                                       Run ~/.claude/scripts/skills-lint
  next [--json]                                     Print the next command to run, from
                                                     deterministic repo state only

Options:
  -h, --help   Show this help message

Exit codes:
  0  ok
  1  doctor found a FAIL, or the underlying tool failed
```
