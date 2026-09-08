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
  [--allow-green] [--force]

Usage:
  flow loop init "<goal>" --verify "<cmd>"
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
