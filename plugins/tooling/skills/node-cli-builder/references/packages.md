# Node.js CLI Package Guide (2025)

Detailed comparison of packages for building terminal CLIs. Read this when you need to choose between alternatives or understand tradeoffs.

## Table of Contents

1. [Interactive Prompts](#interactive-prompts)
2. [Argument Parsing](#argument-parsing)
3. [Colors and Styling](#colors-and-styling)
4. [Spinners and Progress](#spinners-and-progress)
5. [Layout and Formatting](#layout-and-formatting)
6. [Full TUI Frameworks](#full-tui-frameworks)
7. [Utility Packages](#utility-packages)

---

## Interactive Prompts

### @clack/prompts (Recommended)
- **Why**: Beautiful defaults with visual "rail" connecting prompts. Built by the Astro team. Minimal API with `group()` for wizard flows. Includes spinner.
- **When**: Wizard-style multi-step flows, project scaffolders, setup scripts.
- **Size**: ~25KB
- **ESM**: Yes

### @inquirer/prompts
- **Why**: Modular rewrite of Inquirer. Each prompt type is a separate package. Most prompt types of any library (editor, file tree, search, etc.).
- **When**: Complex forms needing specialized prompt types. When you need maximum flexibility.
- **Size**: Varies per prompt package (~5-15KB each)
- **ESM**: Yes

### prompts (legacy)
- **Why**: Dependency-free, lightweight. Still works.
- **When**: Only if you need zero dependencies and simple prompts.
- **Status**: Stale since 2022. Not recommended for new projects.

### enquirer (DO NOT USE)
- Abandoned since 2020. Known bugs. Use @clack/prompts instead.

---

## Argument Parsing

### commander (Recommended)
- **Why**: Most established. Declarative API, auto-generated help, subcommands, option parsing, variadic args. Used by Vue CLI, TypeScript compiler.
- **When**: Any CLI with subcommands or flags.
- **Size**: ~50KB
- **ESM**: Yes

### Node.js `util.parseArgs` (Built-in)
- **Why**: Zero dependencies. Built into Node 18.3+.
- **When**: Simple scripts with a few flags. No subcommands needed.
- **Limitations**: No auto-help generation, no subcommands, no type coercion.

### citty
- **Why**: From the UnJS ecosystem. TypeScript-first, lightweight, subcommands.
- **When**: Projects already in the UnJS orbit (Nuxt, Nitro).
- **Size**: ~10KB

### meow
- **Why**: Extremely minimal. Just parses argv with a help string.
- **When**: Single-purpose CLIs with simple flag needs.
- **ESM**: Yes (ESM-only)

### yargs
- **Why**: Most feature-rich (middleware, async handlers, bash completion generation).
- **When**: Complex CLIs needing middleware chains or shell completion.
- **Downside**: Heavier dependency tree than commander.

---

## Colors and Styling

### picocolors (Recommended for most)
- **Why**: ~14x faster than chalk. ~3.5KB. Covers basic ANSI colors (16 colors).
- **When**: Most CLIs. You rarely need more than basic colors.
- **Limitation**: No 256-color or truecolor. No auto color-level detection.
- **ESM**: Yes

### chalk v5+ (Recommended for advanced color)
- **Why**: Auto-detects color support. Supports 256-color and truecolor (hex codes). Most readable API.
- **When**: You need hex colors, RGB, or advanced color detection.
- **Size**: ~20KB (v5 is dependency-free)
- **ESM**: Yes (ESM-only in v5)

### ansis
- **Why**: TypeScript-first. Drop-in chalk replacement with identical API. Claims fastest benchmarks. Supports truecolor.
- **When**: You want chalk's API with better TypeScript support and performance.

### Node.js `util.styleText` (Built-in)
- **Why**: Zero dependencies. Built into Node 21.7+.
- **When**: Scripts that only need basic styling and can target Node 21.7+.
- **Usage**: `styleText('red', 'Error!')` or `styleText(['bold', 'red'], 'Error!')`

### yoctocolors
- **Why**: Smallest possible (~400 bytes). Basic 16 colors.
- **When**: Size is critical. Simple color needs.

---

## Spinners and Progress

### @clack/prompts spinner
- **Why**: Integrated with Clack's visual style. Matches the prompt aesthetic.
- **When**: Already using @clack/prompts.

### ora (Recommended standalone)
- **Why**: Gold standard. Beautiful defaults, color support, success/fail/warn states, text updates during spin.
- **When**: Any async operation needing a loading indicator.
- **Size**: ~25KB
- **ESM**: Yes (v6+)

### nanospinner
- **Why**: ~5x smaller than ora. Covers 90% of use cases.
- **When**: You want a spinner without ora's weight.

### listr2
- **Why**: Multi-task runner with concurrent/serial tasks, progress, nesting. Used by Angular CLI.
- **When**: Multi-step processes with parallel operations (install deps, generate files, run checks simultaneously).
- **Size**: ~50KB

### cli-progress
- **Why**: Progress bars with customizable format. Multi-bar support.
- **When**: Downloads, file processing, or any operation with measurable progress.

---

## Layout and Formatting

### boxen
- **Why**: Bordered boxes with padding, margin, alignment. Multiple border styles.
- **When**: Highlighting important messages, welcome banners, summaries.
- **ESM**: Yes

### cli-table3
- **Why**: Table output with borders, column width, word-wrap, colors. Community-maintained.
- **When**: Displaying structured data (list of items, configs, statuses).

### figures
- **Why**: Unicode symbol set with Windows CMD fallbacks (check, cross, arrow, etc.).
- **When**: Cross-platform CLIs that need symbols to work on Windows CMD.

### terminal-link
- **Why**: Clickable hyperlinks in supporting terminals. Falls back to `text (url)`.
- **When**: Linking to docs, dashboards, PRs.

### log-symbols
- **Why**: Colored info/success/warning/error symbols. Uses figures internally.
- **When**: Status messages.

---

## Full TUI Frameworks

### Ink (Recommended for complex TUI)
- **Why**: React for the terminal. JSX components, flexbox layout, hooks. Used by Gatsby CLI, Twilio CLI, Shopify CLI.
- **When**: Complex layouts, multiple interactive panels, real-time updates.
- **Requires**: React knowledge
- **Ecosystem**: ink-text-input, ink-select-input, ink-spinner, ink-table, ink-gradient

### terminal-kit
- **Why**: Comprehensive terminal manipulation (cursor, input, drawing).
- **When**: Low-level terminal control without React overhead.
- **Status**: Low activity but functional.

### blessed / neo-blessed (DO NOT USE)
- Abandoned. No Node 20+ testing.

---

## Utility Packages

| Package | Purpose | When to Use |
|---------|---------|-------------|
| `conf` | Persistent config (JSON in XDG dirs) | User preferences, saved state |
| `env-paths` | XDG-compliant paths | Config/data/cache directory resolution |
| `update-notifier` | Check for new versions | Open-source CLIs (use sparingly) |
| `execa` | Better child_process | Spawning other CLIs, running commands |
| `glob` / `fast-glob` | File pattern matching | Finding files by pattern |
| `chokidar` | File watching | Dev servers, watch mode |
| `open` | Open URLs/files in default app | Opening docs, browsers |
| `clipboard-copy` | Copy to clipboard | Copying generated tokens, URLs |
| `strip-ansi` | Remove ANSI codes | Logging to files, processing output |
