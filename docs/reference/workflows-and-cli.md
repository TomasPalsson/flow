# Saved workflows

Discovered from `~/.claude/workflows/*.js` at session start; invoked with `Workflow({ name })`.

## build-slices

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

## plan-review

export const meta = {
  name: 'plan-review',
  description: 'Attack a spec and plan with adversarial lenses, then adjudicate the findings into decisions',
  whenToUse: 'Use before implementation starts to pressure-test a frozen spec and plan',
  phases: [
    { title: 'Attack', detail: 'independent lenses attack the spec and plan' },
    { title: 'Adjudicate', detail: 'one agent merges findings into decisions' },
  ],
}

## research-sweep

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

## review-diff

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

# harness CLI

```

[38;2;122;162;247m[1mharness[0m [38;2;86;95;137m— deterministic project harness CLI[0m

[38;2;187;154;247mUsage:[0m
  harness <command> [options]

[38;2;187;154;247mCommands:[0m
  doctor [--json]                                  Diagnose the ~/.claude deployment
  init [--stack auto|node|python|rust|go] [--dry-run] [--force]
                                                     Scaffold REVIEW.md, PROGRESS.md,
                                                     CLAUDE.md, CI gate, lint thresholds
  check [--fix]                                     Run project quality gates (check-all)
  skills-lint                                       Run ~/.claude/scripts/skills-lint

[38;2;187;154;247mOptions:[0m
  -h, --help   Show this help message

[38;2;187;154;247mExit codes:[0m
  0  ok
  1  doctor found a FAIL, or the underlying tool failed
```
