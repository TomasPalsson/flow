---
name: better-plan
description: Present a plan, design, proposal, or architecture as a polished, interactive, REVIEWABLE page instead of flat markdown — using the locally-installed `better-plan` CLI. Use WHENEVER you are about to show a human a plan they will read and approve: a build/implementation plan, a design doc, an architecture proposal, an API design, a migration plan, an RFC, or a "here's what I'm going to do" before starting work. Renders MDX with diagrams, interactive API specs, annotated code, wireframes, decision records, comparison matrices, timelines, and more, and gives the reviewer an in-page Approve / Request-changes control you can poll. Triggers on - better-plan, /better-plan, "write a plan", "show me the plan", "render the plan", "make a visual plan", "plan this out", "design doc", "proposal", "before you build", "present the plan", "let me review the plan", "plan I can approve", "make the plan readable". Do NOT use for - a one-line answer, a quick code diff, or work you are executing rather than proposing.
---

# Better Plan — visual, reviewable plans

`better-plan` turns a plan you write as **MDX** into a polished page the reviewer opens in a browser, navigates, and **approves in the UI**. Reach for it instead of dumping a wall of markdown whenever a human will *review and sign off* on what you propose.

The command is **globally installed** — just run `better-plan <plan.mdx>`; you never need the tool's repo path.

## When to use it (the decision)

**Use a visual plan when** you are *proposing* something a human will review: a build/implementation plan, design doc, architecture, API design, migration, or "here's my approach before I start." Especially when the plan has structure prose hides badly — a flow, an API surface, code to annotate, a UI to sketch, options to compare.

**Don't** for: a one-line answer, a quick diff, FAQ-style replies, or work you're *executing* rather than proposing. A plan page is for review, not for narration.

> The payoff is the **approval gate**: present the plan, then gate your next step on the reviewer's decision (below). That turns "I think this is what you want" into "you approved exactly this."

## The workflow

1. **Write** the plan as one `.mdx` file (default `plan.mdx`). Lead with `<PlanHeader>`, then top-level `##` headings — each `##` becomes a nav entry, so they are the plan's spine.
2. **Render**: `better-plan ./plan.mdx` → it **opens the plan in the browser automatically** and prints the `localhost` URL (pass `--no-open` to suppress the auto-open).
3. **Iterate**: edit and save — the open page live-reloads in under a second (no restart). A compile error shows a located overlay (file + line) and preserves the last good render; fix and save to recover.
4. **Get sign-off**: the reviewer uses the in-page review bar (next section).

```bash
better-plan ./plan.mdx                 # render one plan → prints a localhost URL
better-plan ./plans/                   # a directory renders all .mdx files as one page (filename order)
better-plan ./plan.mdx --port 5000     # prefer a port (next free is used if taken)
better-plan ./plan.mdx --theme dark    # initial theme
better-plan ./plan.mdx --wait-approval # block until the reviewer decides, then exit
```

## Getting the reviewer's approval (gate your work on this)

Every rendered plan has a sticky review bar: the reviewer clicks **Approve plan**, or **Request changes** which opens a dialog asking what to change. Learn the decision two ways:

```bash
# A) Blocking — the command exits when the reviewer decides:
better-plan ./plan.mdx --wait-approval   # exit 0 = approved, exit 2 = changes requested (note printed)

# B) Polling — run the server, then poll the status endpoint until it leaves "pending":
curl -s http://localhost:4711/__bp/status
#   {"status":"pending"}                                  → keep waiting
#   {"status":"approved","at":"…"}                        → proceed
#   {"status":"changes-requested","note":"…","at":"…"}    → revise per the note, re-render
```

Poll loop you can drop into a shell:

```bash
while curl -s http://localhost:4711/__bp/status | grep -q '"status":"pending"'; do sleep 3; done
curl -s http://localhost:4711/__bp/status   # → the decision (+ note)
```

**Do not start building until `status` is `approved`.** If it's `changes-requested`, read the `note`, revise the MDX (it live-reloads), and wait again.

## Answering questions while the plan is open

A served plan also has a floating **Ask Claude** dock — the reviewer can ask free-text questions about the plan at any time. Watch for them and answer in one of two ways:

- **Revise the plan** — edit the MDX (it live-reloads; the changed sections flash). Best when the question exposes a real gap.
- **Reply in text** — a written answer shown in the dock. Best for clarifying intent without changing the plan.

Read questions and post answers over the same local channel (use the port from the URL printed at launch):

```bash
# the running thread — or read the sibling <plan>.qa.json (same data, no server needed)
curl -s http://localhost:4711/__bp/qa
#   {"entries":[{"id":"q1","question":"…","askedAt":"…"}]}   → an entry with no "answer" is waiting on you

# answer in text…
curl -s -X POST http://localhost:4711/__bp/answer -H 'content-type: application/json' \
  -d '{"id":"q1","kind":"text","text":"…"}'
# …or note that you revised the plan (after editing the MDX)
curl -s -X POST http://localhost:4711/__bp/answer -H 'content-type: application/json' \
  -d '{"id":"q1","kind":"plan-update"}'
```

Poll `GET /__bp/qa` (or the `<plan>.qa.json` sidecar) while the plan is open so you catch questions as they arrive — the open page shows each reply the instant you post it.

## Authoring rules (read before writing)

- **One `<PlanHeader>` first** — the masthead (title, summary, status, effort, author).
- **Top-level `##` headings are the spine** — they generate the nav. Keep them scannable (Context, Architecture, API, Data, Risks…).
- **Reach for a component only when it beats prose.** A flow → `<Diagram>`. An endpoint → `<APISpec>`. A tradeoff → `<Comparison>` or `<ADR>`. Don't narrate what a diagram already shows.
- **Required props matter**: a missing required prop renders a labeled warning slot in place of the component (it never crashes the page) — but it's visible, so get them right. Required props are called out in the catalog.
- **Props are JSX**: strings in quotes, arrays/objects in `{...}`, multi-line code/DSL in a template literal `` {`…`} ``.
- **Aesthetic**: the design is a "marked-up blueprint" — teal carries structure, amber carries annotation. You don't style anything; components are pre-styled. Keep prose tight (the page caps the reading measure).

## NEVER (the authoring landmines)

- **NEVER write Mermaid syntax in `<Diagram>`** (`graph LR`, `-->`, `[Label]`). The engine only understands `A -> B` arrows + `[accent]` — Mermaid renders a parse error. This is the #1 mistake.
- **NEVER omit a required prop** (`<PlanHeader>` `title`, `<APISpec>` `method`+`path`, `<AnnotatedCode>` `code`, `<Wireframe>`/`<FileTree>` `children`, `<Collapsible>` `summary`, `<Stat>` `value`, `<Comparison>` `columns`+`rows`, `<ADR>`/`<Step>` `title`, `<Entity>` `name`, `<Checklist>`/`<Timeline>` `items`). A missing one renders a visible warning slot, not the component.
- **NEVER use `###` for a main section** — only top-level `##` headings generate the nav. Sub-headings vanish from the spine.
- **NEVER pass `_index` to `<Step>`** — `<Steps>` injects it; passing it manually breaks numbering.
- **NEVER skip `<PlanHeader>` or bury it mid-document** — it's the masthead; it goes first, once.
- **NEVER forget the template literal for multi-line props** — DSL/code must be `` {`…`} ``, not a bare string, or it won't compile.

## Choosing a component (when each beats prose)

The test for every component: *does the reviewer learn faster from this than from the paragraph it replaces?* If not, write the sentence.

| You have… | Use | Not |
|---|---|---|
| A sequence/flow/architecture | `<Diagram>` | a paragraph describing arrows |
| An HTTP endpoint contract | `<APISpec>` | a fenced JSON blob |
| Code worth pointing at specific lines | `<AnnotatedCode>` | code + "note that line 2…" prose |
| A UI you're proposing | `<Wireframe>` | "it'll have a sidebar and…" |
| ≥3 options weighed on ≥2 axes | `<Comparison>` | bullet lists of pros/cons |
| A consequential decision | `<ADR>` | a buried paragraph |
| A multi-step procedure | `<Steps>` | a numbered markdown list (fine for ≤2 trivial steps) |
| One fact, one option, one step | a sentence | a single-row `<Comparison>` / single `<Step>` |

## Component quick-reference

The MUST-know four plus the masthead — full catalog (every prop, every gotcha) in the reference file:

| Component | One-liner | Required |
|---|---|---|
| `<PlanHeader>` | Masthead: title, summary, status, effort, author | `title` |
| `<Diagram>` | Flow/sequence/state/ER via arrow DSL (`A -> B`), auto-laid-out, zoom/pan | — |
| `<APISpec>` | Interactive endpoint: method, path, params, example | `method`, `path` |
| `<AnnotatedCode>` | Syntax-highlighted code with amber margin notes on line ranges | `code` |
| `<Wireframe>` | Low-fi UI sketch in a browser/phone frame | `children` |
| `<Callout>` | note / tip / warning / danger / success admonition | — |
| `<Steps>`/`<Tabs>`/`<Collapsible>` | Procedure, tabbed views, disclosure | (Step needs `title`) |
| `<Comparison>`/`<ADR>` | Option matrix, decision record | (`columns`,`rows`) / `title` |
| `<Stat>`/`<Checklist>`/`<DataModel>`/`<Timeline>`/`<Badge>` | Metrics, tasks, schema, roadmap, status pills | (Stat `value`; others vary) |

**Get the live catalog from the CLI** — the fastest source of truth, generated from the installed tool:

```bash
better-plan components            # every component, its props (required marked *), and an example
better-plan components Diagram    # one component's full shape
better-plan components --json     # machine-readable (name, props[{name,type,required,note}], example)
```

**MANDATORY — READ ENTIRE FILE before authoring components**: Load [`references/components.md`](references/components.md). It has every component's exact props, required props, MDX example, and gotchas (the Diagram arrow-DSL `A -> B : label` / `[accent]`; AnnotatedCode `lines` ranges like `"2-4"`; FileTree's indented-text parsing with `# comment` and `<-- chip`; the sub-components `<Step>`/`<Tab>`/`<Entity>`).

## The Diagram engine (NOT Mermaid)

Diagrams use a custom engine — **Mermaid syntax does not work**. Declare edges with arrows:

```mdx
<Diagram type="flow" caption="Render pipeline">
{`MDX file -> compile -> render [accent] -> localhost`}
</Diagram>
```

`A -> B` makes an edge; `A -> B : label` labels it; a node ending `[accent]` is tinted amber. Or pass `nodes`/`edges` props for richer graphs. Big diagrams zoom (wheel) and pan (drag) in the page.

## Recovery

| Symptom | Fix |
|---|---|
| CLI exits "path not found" | Check the path; no server started. |
| Page shows a located compile error (file + line) | Usually a missing required prop or an unclosed tag at that line. |
| One component shows an inline error/warning slot | That component's props/syntax are wrong; the rest of the page is fine. |
| A `<Diagram>` shows a parse error | You used Mermaid syntax — switch to `A -> B` arrows. |
| Port busy | The tool already chose the next free port — use the URL it printed. |

## When NOT to author a component

A single fact → a sentence. Executing the plan, not proposing it → this skill renders, it doesn't build. The reviewer only wants a diff → show the code.
