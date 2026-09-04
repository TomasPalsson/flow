---
name: node-cli-builder
description: Build beautiful, production-quality Node.js terminal CLI applications with excellent UX. Use this skill whenever the user wants to create a CLI tool, terminal app, command-line script, interactive prompt, or TUI with Node.js/JavaScript. Also trigger when they mention packages like clack, inquirer, commander, ora, ink, or ask about terminal UI patterns, ANSI styling, or interactive prompts.
---

# Node.js CLI Builder

Build terminal CLI applications that feel polished, fast, and delightful. This skill covers package selection, UX patterns, interactive prompts, styling, error handling, and accessibility — everything needed to create CLIs that users love.

## Core Philosophy

1. **Speed is king** — CLI must show output in <100ms. Lazy-load everything heavy.
2. **Progressive disclosure** — simple by default, powerful when needed.
3. **Respect the terminal** — degrade gracefully (no-color, no-TTY, CI, piping).
4. **Feedback always** — never leave the user wondering what's happening.
5. **Errors are opportunities** — tell them what broke, why, and how to fix it.

## Package Selection

Choose packages based on the CLI's complexity. Always prefer modern, maintained, lightweight packages.

### Tier 1: Minimal CLI (single-purpose scripts)

Zero or near-zero external dependencies. Use Node.js built-ins.

```javascript
import { parseArgs } from 'node:util';        // Flag parsing (Node 18.3+)
import { createInterface } from 'node:readline'; // Basic prompts
import { styleText } from 'node:util';          // Colors (Node 21.7+)
```

For Node <21.7, use **picocolors** (~3.5KB, 14x faster than chalk):
```javascript
import pc from 'picocolors';
```

### Tier 2: Interactive CLI (wizards, prompts, spinners)

The recommended modern stack:

| Need | Package | Why |
|------|---------|-----|
| Argument parsing | `commander` | Battle-tested, auto-help, subcommands |
| Interactive prompts | `@clack/prompts` | Beautiful defaults, visual rail connecting prompts, spinner built-in |
| Colors | `picocolors` | Fastest, smallest, covers 90% of needs |
| Spinners | Built into `@clack/prompts`, or `ora` standalone | |
| Boxes/frames | `boxen` | Bordered content sections |

```json
{
  "type": "module",
  "dependencies": {
    "commander": "^13.0.0",
    "@clack/prompts": "^0.9.0",
    "picocolors": "^1.1.0"
  }
}
```

### Tier 3: Full TUI (dashboards, complex layouts)

Use **Ink** (React for the terminal) only when you genuinely need complex layouts:

```json
{
  "dependencies": {
    "ink": "^5.0.0",
    "react": "^18.0.0",
    "ink-text-input": "^6.0.0",
    "ink-select-input": "^6.0.0"
  }
}
```

### Packages to Avoid

| Package | Why | Use Instead |
|---------|-----|-------------|
| `enquirer` | Abandoned since 2020 | `@clack/prompts` or `@inquirer/prompts` |
| `blessed` / `neo-blessed` | Abandoned since 2017 | `ink` |
| `chalk` v4 | CommonJS, heavy | `picocolors` or `chalk` v5+ |
| `vorpal`, `caporal` | Abandoned | `commander` |
| `prompts` | Stale since 2022 | `@clack/prompts` |

## Project Structure

```
my-cli/
├── bin/
│   └── my-cli.js          # Entry point (#!/usr/bin/env node)
├── src/
│   ├── commands/           # Subcommand handlers
│   │   ├── init.js
│   │   └── build.js
│   ├── ui/                 # Reusable UI components
│   │   ├── colors.js       # Color palette + helpers
│   │   ├── format.js       # Output formatting (boxes, tables, lists)
│   │   └── prompts.js      # Custom prompt wrappers
│   └── utils/              # Business logic
├── package.json
└── README.md
```

**Entry point pattern** (`bin/my-cli.js`):

```javascript
#!/usr/bin/env node

// Lazy-load to keep startup fast
const { program } = await import('commander');

program
  .name('my-cli')
  .description('What this CLI does')
  .version('1.0.0');

program
  .command('init')
  .description('Initialize a new project')
  .argument('[name]', 'project name')
  .action(async (name) => {
    // Lazy-load the handler
    const { init } = await import('../src/commands/init.js');
    await init(name);
  });

program.parse();
```

## Color Palette

Define your colors once in a central module and reference them everywhere. Keep it semantic — colors should map to meaning, not aesthetics.

```javascript
// src/ui/colors.js
import pc from 'picocolors';

export const c = {
  // Semantic
  success: pc.green,
  error: pc.red,
  warn: pc.yellow,
  info: pc.cyan,

  // UI elements
  primary: pc.cyan,
  muted: pc.dim,
  accent: pc.magenta,
  bold: pc.bold,

  // Composite helpers
  label: (text) => pc.bold(pc.cyan(text)),
  hint: (text) => pc.dim(`(${text})`),
  path: (text) => pc.underline(pc.dim(text)),
  cmd: (text) => pc.bold(pc.yellow(text)),
  key: (text) => pc.bold(pc.white(text)),
};
```

**Color rules:**
- **3-4 colors max** in any single output. Every color must mean something.
- **Red** = errors, destructive. **Green** = success, created. **Yellow** = warnings, important. **Cyan** = info, interactive. **Dim** = secondary.
- Never use color as the **only** signifier — always pair with symbols (checkmark, X, !, i).

## Icons and Symbols

Use Unicode symbols that work across platforms. Only use Nerd Font glyphs if the tool is for developers who are likely to have them (and provide fallbacks).

```javascript
// src/ui/icons.js

// Safe Unicode (works everywhere)
export const icons = {
  success:  '✓',
  error:    '✗',
  warning:  '!',
  info:     'i',
  arrow:    '❯',
  dot:      '•',
  dash:     '─',
  ellipsis: '…',
  pointer:  '▸',
};

// Nerd Font (developer tools only)
export const nerd = {
  folder:  '',
  file:    '',
  git:     '',
  node:    '',
  python:  '',
  rust:    '',
};

// Auto-detect: use Nerd if $TERM_PROGRAM suggests a modern terminal
export const isModernTerminal = ['iTerm.app', 'WezTerm', 'ghostty', 'Alacritty']
  .includes(process.env.TERM_PROGRAM);
```

## Interactive Prompts with @clack/prompts

Clack provides a beautiful "visual rail" that connects prompts. This is the recommended approach for wizard-style flows.

```javascript
import * as p from '@clack/prompts';
import pc from 'picocolors';

export async function createProject() {
  p.intro(pc.bgCyan(pc.black(' Create Project ')));

  const project = await p.group(
    {
      name: () =>
        p.text({
          message: 'Project name',
          placeholder: 'my-app',
          validate: (v) => {
            if (!v) return 'Name is required';
            if (!/^[a-z0-9-]+$/.test(v)) return 'Use lowercase letters, numbers, hyphens';
          },
        }),

      framework: () =>
        p.select({
          message: 'Pick a framework',
          options: [
            { value: 'react', label: 'React', hint: 'recommended' },
            { value: 'vue',   label: 'Vue' },
            { value: 'svelte', label: 'Svelte' },
          ],
        }),

      typescript: () =>
        p.confirm({
          message: 'Add TypeScript?',
          initialValue: true,
        }),

      install: () =>
        p.confirm({
          message: 'Install dependencies?',
          initialValue: true,
        }),
    },
    {
      onCancel: () => {
        p.cancel('Setup cancelled.');
        process.exit(0);
      },
    }
  );

  const s = p.spinner();
  s.start('Creating project');
  // ... do work ...
  s.stop('Project created');

  p.note(
    `cd ${project.name}\nnpm run dev`,
    'Next steps'
  );

  p.outro('Done! Happy coding.');
}
```

## Error Handling

Errors are the most important UX surface. A good error message saves hours.

```javascript
// src/ui/errors.js
import pc from 'picocolors';
import { icons } from './icons.js';

export function formatError(message, { cause, suggestion, code } = {}) {
  const lines = [];

  lines.push(`${pc.red(icons.error)}  ${pc.bold(pc.red(message))}`);

  if (cause) {
    lines.push(`   ${pc.dim(cause)}`);
  }

  if (suggestion) {
    lines.push('');
    lines.push(`   ${pc.dim('To fix this, run:')}`);
    lines.push(`   ${pc.cyan('$')} ${pc.bold(suggestion)}`);
  }

  if (code) {
    lines.push('');
    lines.push(`   ${pc.dim(`Error code: ${code}`)}`);
  }

  return lines.join('\n');
}

// Usage
console.error(formatError('Config file not found', {
  cause: 'Expected ~/.config/mycli/config.json',
  suggestion: 'mycli init',
  code: 'E001',
}));
```

**Error principles:**
1. What went wrong (plain language)
2. Why (context: file path, expected vs received)
3. How to fix it (concrete command or action)
4. Error code (for searchability)

## Signal Handling

Always handle Ctrl+C and cleanup gracefully.

```javascript
// At the top of your entry point
function setupSignalHandlers() {
  const cleanup = () => {
    // Restore cursor, clean temp files, etc.
    process.stderr.write('\x1B[?25h'); // Show cursor
  };

  process.on('SIGINT', () => {
    cleanup();
    process.stdout.write('\n');
    process.exit(130); // 128 + SIGINT(2)
  });

  process.on('SIGTERM', () => {
    cleanup();
    process.exit(143); // 128 + SIGTERM(15)
  });

  process.on('exit', cleanup);
}
```

## Accessibility and Environment Detection

```javascript
// src/ui/env.js

export const env = {
  // Color support
  noColor: 'NO_COLOR' in process.env || process.env.TERM === 'dumb',
  forceColor: 'FORCE_COLOR' in process.env,

  // Terminal capabilities
  isTTY: process.stdout.isTTY === true,
  isCI: 'CI' in process.env,

  // Interactivity: only prompt when connected to a real terminal
  isInteractive: process.stdout.isTTY && process.stdin.isTTY && !('CI' in process.env),

  // Terminal dimensions
  columns: process.stdout.columns || 80,
  rows: process.stdout.rows || 24,
};
```

**Rules:**
- When `!isTTY` (piped): no colors, no spinners, no prompts. Plain text output.
- When `isCI`: no interactive prompts, no animations. Structured output.
- When `noColor`: strip all ANSI codes. Use `NO_COLOR` env var (no-color.org standard).
- Always support `--json` flag for machine-readable output.
- Always support `--quiet` / `-q` for silent operation.

## Output Formatting

### Boxed Content

```javascript
import boxen from 'boxen';

const message = boxen('Project created successfully!', {
  padding: 1,
  margin: { top: 1, bottom: 1 },
  borderStyle: 'round',
  borderColor: 'cyan',
});
```

### Structured Lists

```javascript
function formatList(items, { bullet = '•', indent = 2 } = {}) {
  const pad = ' '.repeat(indent);
  return items.map(item => `${pad}${pc.dim(bullet)} ${item}`).join('\n');
}

// Usage
console.log(formatList([
  `${pc.green('✓')} chalk@5.3.0`,
  `${pc.green('✓')} ora@8.0.1`,
  `${pc.green('✓')} commander@12.0.0`,
]));
```

### Key-Value Display

```javascript
function formatKeyValue(pairs, { separator = '  ', labelWidth = 0 } = {}) {
  const maxLen = labelWidth || Math.max(...pairs.map(([k]) => k.length));
  return pairs
    .map(([key, val]) => `  ${pc.bold(key.padEnd(maxLen))}${separator}${val}`)
    .join('\n');
}
```

## Loading States

```javascript
import * as p from '@clack/prompts';

// Clack spinner (preferred when using Clack)
const s = p.spinner();
s.start('Installing dependencies');
await install();
s.stop('Dependencies installed');

// Ora spinner (standalone use)
import ora from 'ora';
const spinner = ora('Loading configuration').start();
try {
  await loadConfig();
  spinner.succeed('Configuration loaded');
} catch (err) {
  spinner.fail('Failed to load configuration');
}
```

**Rules:**
- Any operation >100ms gets a spinner
- Any operation >2s gets a progress indicator or count
- Always show what is being done: `Installing dependencies (3/17)`
- On completion, replace spinner with success/failure symbol

## Keyboard Navigation

When building custom interactive components (not using Clack/Inquirer):

```javascript
import { emitKeypressEvents } from 'node:readline';

emitKeypressEvents(process.stdin);
if (process.stdin.isTTY) process.stdin.setRawMode(true);

process.stdin.on('keypress', (str, key) => {
  if (key.ctrl && key.name === 'c') process.exit(130);

  switch (key.name) {
    case 'up':
    case 'k':          // vim up
      moveCursor(-1);
      break;
    case 'down':
    case 'j':          // vim down
      moveCursor(1);
      break;
    case 'return':
      confirmSelection();
      break;
    case 'escape':
      cancel();
      break;
  }
});
```

**Standard keybindings:**
- `j/k` or `Up/Down` — navigate
- `Enter` — confirm
- `Space` — toggle (multi-select)
- `Ctrl+C` — always exits
- `Esc` — back/cancel
- Type to filter/search

## Exit Codes

```javascript
// Always use explicit exit codes
process.exit(0);   // Success
process.exit(1);   // Application error
process.exit(2);   // Usage error (bad flags, missing args)
process.exit(130); // SIGINT (Ctrl+C)
```

Never exit 0 on failure. Use stderr for errors, stdout for data.

## Piping and Composability

```javascript
// Detect if output is being piped
if (!process.stdout.isTTY) {
  // Machine mode: plain output, no decorations
  console.log(JSON.stringify(result));
  process.exit(0);
}

// Interactive mode: rich output
```

Support `--json` for structured output:
```bash
mycli list                    # Pretty, colored table
mycli list --json             # JSON array
mycli list --json | jq '.[0]' # Composable
```

## Performance

Startup time is the single most impactful quality signal.

```javascript
// BAD: eager imports block startup
import chalk from 'chalk';
import ora from 'ora';
import boxen from 'boxen';
import { table } from 'cli-table3';

// GOOD: lazy imports only when needed
const program = (await import('commander')).program;

program
  .command('build')
  .action(async () => {
    const ora = (await import('ora')).default;
    const spinner = ora('Building...').start();
    // ...
  });
```

**Targets:**
- <100ms to first output (feels instant)
- <300ms acceptable for complex CLIs
- >500ms needs a loading indicator

## Help Text

```
mycli - short description of what it does

Usage:
  mycli <command> [options]

Commands:
  init          Initialize a new project
  build         Build for production
  dev           Start development server

Options:
  -v, --verbose    Show detailed output
  -q, --quiet      Suppress output
  --no-color       Disable colors
  -h, --help       Show help
  --version        Show version

Examples:
  $ mycli init my-app
  $ mycli build --minify
  $ mycli dev --port 3000
```

**Rules:**
- Examples are mandatory — users learn by example
- Show defaults: `--port <number>  (default: 3000)`
- Support both `-h` and `--help`
- Support `--version`

## Quick Reference: When to Read More

For detailed package comparisons and alternatives, read `references/packages.md`.
For complete template files ready to copy, read `references/templates.md`.
