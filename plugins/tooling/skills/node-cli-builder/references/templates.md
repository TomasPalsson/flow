# CLI Templates

Ready-to-use templates for common CLI patterns. Copy and adapt these.

## Table of Contents

1. [Minimal Script (no deps)](#minimal-script)
2. [Interactive Wizard (Clack)](#interactive-wizard)
3. [Subcommand CLI (Commander + Clack)](#subcommand-cli)
4. [Custom Interactive Menu (readline)](#custom-interactive-menu)

---

## Minimal Script

A single-file CLI with no external dependencies. Uses Node.js built-ins only.

```javascript
#!/usr/bin/env node

import { parseArgs } from 'node:util';
import { readFile, writeFile } from 'node:fs/promises';

// ─── Config ────────────────────────────────────────────
const { values: flags, positionals: args } = parseArgs({
  options: {
    output: { type: 'string', short: 'o', default: 'stdout' },
    verbose: { type: 'boolean', short: 'v', default: false },
    help: { type: 'boolean', short: 'h', default: false },
  },
  allowPositionals: true,
  strict: true,
});

// ─── Help ──────────────────────────────────────────────
if (flags.help || args.length === 0) {
  console.log(`
my-script - process files quickly

Usage:
  my-script <file> [options]

Options:
  -o, --output <path>   Output file (default: stdout)
  -v, --verbose         Show detailed output
  -h, --help            Show this help

Examples:
  $ my-script input.txt
  $ my-script input.txt -o output.txt
  $ my-script input.txt | grep "pattern"
  `.trim());
  process.exit(0);
}

// ─── Main ──────────────────────────────────────────────
const isTTY = process.stdout.isTTY;

try {
  const content = await readFile(args[0], 'utf-8');

  // Process content...
  const result = content.toUpperCase();

  if (flags.output === 'stdout') {
    process.stdout.write(result);
  } else {
    await writeFile(flags.output, result);
    if (isTTY) console.error(`Written to ${flags.output}`);
  }
} catch (err) {
  console.error(`Error: ${err.message}`);
  if (flags.verbose) console.error(err.stack);
  process.exit(1);
}
```

---

## Interactive Wizard

A multi-step wizard using @clack/prompts. Great for project scaffolders, setup scripts, configuration generators.

```javascript
#!/usr/bin/env node

import * as p from '@clack/prompts';
import pc from 'picocolors';
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

// ─── Signal Handling ───────────────────────────────────
process.on('SIGINT', () => {
  process.stdout.write('\n');
  process.exit(130);
});

// ─── Main ──────────────────────────────────────────────
async function main() {
  console.clear();
  p.intro(pc.bgCyan(pc.black(' Create App ')));

  const config = await p.group(
    {
      name: () =>
        p.text({
          message: 'Project name',
          placeholder: 'my-app',
          validate: (value) => {
            if (!value?.trim()) return 'Name is required';
            if (!/^[a-z0-9][a-z0-9._-]*$/.test(value)) {
              return 'Use lowercase letters, numbers, hyphens, dots, underscores';
            }
            if (existsSync(value)) return `Directory "${value}" already exists`;
          },
        }),

      template: () =>
        p.select({
          message: 'Choose a template',
          options: [
            { value: 'basic',    label: 'Basic',      hint: 'minimal setup' },
            { value: 'api',      label: 'API Server',  hint: 'Express + routing' },
            { value: 'fullstack', label: 'Full Stack', hint: 'React + API' },
          ],
        }),

      features: () =>
        p.multiselect({
          message: 'Select features',
          options: [
            { value: 'typescript', label: 'TypeScript',  hint: 'recommended' },
            { value: 'eslint',     label: 'ESLint' },
            { value: 'prettier',   label: 'Prettier' },
            { value: 'testing',    label: 'Testing',     hint: 'vitest' },
            { value: 'docker',     label: 'Docker' },
          ],
          required: false,
        }),

      git: () =>
        p.confirm({
          message: 'Initialize git repository?',
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

  // ─── Execute ───────────────────────────────────────
  const s = p.spinner();

  s.start('Creating project structure');
  mkdirSync(join(config.name, 'src'), { recursive: true });
  // ... scaffold files based on config.template and config.features ...
  s.stop('Project structure created');

  if (config.git) {
    s.start('Initializing git');
    // ... run git init ...
    s.stop('Git initialized');
  }

  // ─── Summary ───────────────────────────────────────
  p.note(
    [
      `${pc.bold('Template:')}  ${config.template}`,
      `${pc.bold('Features:')}  ${config.features.join(', ') || 'none'}`,
      `${pc.bold('Git:')}       ${config.git ? 'yes' : 'no'}`,
      '',
      `${pc.dim('Next steps:')}`,
      `  cd ${config.name}`,
      `  npm install`,
      `  npm run dev`,
    ].join('\n'),
    'Project created'
  );

  p.outro(pc.green('Done! Happy coding.'));
}

main().catch((err) => {
  console.error(pc.red(`\nFatal: ${err.message}`));
  process.exit(1);
});
```

---

## Subcommand CLI

A multi-command CLI using Commander with lazy-loaded subcommands and Clack for interactive parts.

```javascript
#!/usr/bin/env node

// bin/mycli.js — entry point, keep imports minimal for fast startup

import { Command } from 'commander';

const program = new Command();

program
  .name('mycli')
  .description('A tool for managing widgets')
  .version('1.0.0');

// ─── Commands (lazy-loaded) ────────────────────────────

program
  .command('init')
  .description('Create a new widget project')
  .argument('[name]', 'project name')
  .option('-t, --template <name>', 'template to use', 'basic')
  .action(async (name, opts) => {
    const { init } = await import('../src/commands/init.js');
    await init(name, opts);
  });

program
  .command('list')
  .description('List all widgets')
  .option('--json', 'output as JSON')
  .option('-q, --quiet', 'only show names')
  .action(async (opts) => {
    const { list } = await import('../src/commands/list.js');
    await list(opts);
  });

program
  .command('deploy')
  .description('Deploy widgets to production')
  .argument('<widget>', 'widget to deploy')
  .option('--dry-run', 'preview changes without applying')
  .option('--force', 'skip confirmation')
  .action(async (widget, opts) => {
    const { deploy } = await import('../src/commands/deploy.js');
    await deploy(widget, opts);
  });

program.parse();
```

```javascript
// src/commands/deploy.js — example subcommand with confirmation

import * as p from '@clack/prompts';
import pc from 'picocolors';

export async function deploy(widget, { dryRun, force }) {
  if (dryRun) {
    console.log(pc.dim('Dry run mode — no changes will be applied\n'));
  }

  // Fetch deployment info
  const info = await getDeploymentInfo(widget);

  // Show what will happen
  console.log(`  ${pc.bold('Widget:')}    ${widget}`);
  console.log(`  ${pc.bold('Version:')}   ${info.version}`);
  console.log(`  ${pc.bold('Target:')}    ${info.target}`);
  console.log(`  ${pc.bold('Changes:')}   ${info.changes} files\n`);

  if (dryRun) {
    console.log(pc.dim('Dry run complete. No changes applied.'));
    return;
  }

  // Confirm destructive action
  if (!force && process.stdout.isTTY) {
    const confirmed = await p.confirm({
      message: `Deploy ${pc.bold(widget)} to ${pc.bold(info.target)}?`,
    });

    if (!confirmed || p.isCancel(confirmed)) {
      p.cancel('Deployment cancelled.');
      process.exit(0);
    }
  }

  const s = p.spinner();
  s.start(`Deploying ${widget}`);
  await performDeploy(widget);
  s.stop(`${widget} deployed to ${info.target}`);

  console.log(`\n  ${pc.green('✓')} Live at ${pc.underline(info.url)}`);
}
```

---

## Custom Interactive Menu

When you need more control than @clack/prompts provides — a custom menu with vim keybindings, built with raw readline.

```javascript
// src/ui/menu.js
import pc from 'picocolors';
import { emitKeypressEvents, createInterface } from 'node:readline';

/**
 * Display an interactive menu with vim keybindings.
 * @param {string} title - Menu title
 * @param {{ label: string, value: string, hint?: string }[]} items
 * @returns {Promise<string>} Selected value
 */
export function menu(title, items) {
  return new Promise((resolve) => {
    let cursor = 0;
    const rl = createInterface({ input: process.stdin, output: process.stdout });

    emitKeypressEvents(process.stdin, rl);
    if (process.stdin.isTTY) process.stdin.setRawMode(true);

    function render() {
      // Clear previous render
      process.stdout.write(`\x1B[${items.length + 3}A\x1B[0J`);
      draw();
    }

    function draw() {
      const lines = [];
      lines.push(`  ${pc.bold(title)}`);
      lines.push('');

      items.forEach((item, i) => {
        const selected = i === cursor;
        const pointer = selected ? pc.cyan('❯') : ' ';
        const label = selected ? pc.cyan(pc.bold(item.label)) : item.label;
        const hint = item.hint ? pc.dim(` (${item.hint})`) : '';
        lines.push(`  ${pointer} ${label}${hint}`);
      });

      lines.push('');
      lines.push(pc.dim('  ↑/k up  ↓/j down  enter select  esc cancel'));
      process.stdout.write(lines.join('\n') + '\n');
    }

    function cleanup() {
      if (process.stdin.isTTY) process.stdin.setRawMode(false);
      rl.close();
    }

    // Initial draw
    draw();

    process.stdin.on('keypress', (str, key) => {
      if (key.ctrl && key.name === 'c') {
        cleanup();
        process.exit(130);
      }

      switch (key.name) {
        case 'up':
        case 'k':
          cursor = (cursor - 1 + items.length) % items.length;
          render();
          break;
        case 'down':
        case 'j':
          cursor = (cursor + 1) % items.length;
          render();
          break;
        case 'return':
          cleanup();
          resolve(items[cursor].value);
          break;
        case 'escape':
        case 'q':
          cleanup();
          resolve(null);
          break;
      }
    });
  });
}
```
