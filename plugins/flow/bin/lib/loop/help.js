'use strict';

// loop/help.js — `flow loop --help` and `flow loop <cmd> --help` text.

function printTopHelp() {
  process.stdout.write(`flow loop — run a task until a deterministic verifier passes

Usage:
  flow loop <command> [options]

Commands:
  init "<goal>" --verify "<cmd>" [options]   Arm a loop contract (red first)
  check [--json]                             Run the verifier + tamper check once
  tick [--json|--hook] [--session <id>]      One state transition (K-H)
  run [options]                              Fresh-shape driver (outer claude -p loop)
  status [--json]                            Contract summary + tail of verify.last
  stop [--reason <text>]                     Stop the active loop
  log [-n N]                                 Last N log lines (default 20)

Options:
  -h, --help   Show this help message
`);
}

const SUB_HELP = {
  init: `flow loop init "<goal>" --verify "<cmd>" [--shape session|fresh]
  [--prompt-file <path> | --prompt "<text>"] [--session <id>]
  [--max-iterations N] [--max-minutes N] [--max-usd N] [--stall-after N]
  [--verify-timeout S] [--permission-mode M] [--model M] [--max-turns N]
  [--allow-green] [--force] [--target <dir>]

  --target <dir>   byte-freeze <dir> into the contract (target_sha); tamper
                    check fires if it changes. Use for a ui-score baseline
                    dir, e.g. --target .loop-target

Usage:
  flow loop init "<goal>" --verify "<cmd>"
`,
  'init-metric': `flow loop init "<goal>" --metric "<cmd printing one number>" --direction max|min
  [--runs N] [--min-attempts N] [--target <value>] [--verify "<regression gate>"]
  [--holdout "<cmd printing one number>"]
  [--shape session|fresh] [--max-iterations N] [--max-minutes N] [--max-usd N]

  Hillclimb form: keep a commit only if the median of --runs (default 3) beats
  the best by more than the noise measured at init and --verify (the optional
  regression gate) is green; otherwise the commit is undone with a revert
  commit. Every attempt is a row in .claude/loop/decisions.tsv. Init refuses a
  dirty tree, a metric that prints no number, and a spread larger than the
  distance to --target. With --metric, --target is the number to reach.
  --min-attempts N holds back stall stops and the target finish until N
  attempts were judged. A candidate that wins by less than twice the noise is
  measured once more and kept only if both medians beat.
  --holdout runs only for a candidate that beats best; a holdout that regresses
  by more than its own noise reverts the commit. Its values go to
  .claude/loop/holdout.tsv, never to the prompt or decisions.tsv. Files named
  in the command are tamper-protected; add cases it reads without naming them
  with --test-files.
`,
  check: `flow loop check [--json]

Usage:
  flow loop check [--json]
`,
  tick: `flow loop tick [--json|--hook] [--session <id>]

Usage:
  flow loop tick [--hook]
`,
  run: `flow loop run [--max-iterations N] [--max-minutes N] [--max-usd N]
  [--permission-mode M] [--model M] [--max-turns N] [--dry-run]
  [--no-checkpoint] [--worktree]

Usage:
  flow loop run [--dry-run]
`,
  status: `flow loop status [--json]

Usage:
  flow loop status
`,
  stop: `flow loop stop [--reason <text>]

Usage:
  flow loop stop
`,
  log: `flow loop log [-n N]

Usage:
  flow loop log [-n N]
`,
};

function printSubHelp(cmd) {
  process.stdout.write(SUB_HELP[cmd] || SUB_HELP.init);
}

module.exports = { printTopHelp, printSubHelp };
