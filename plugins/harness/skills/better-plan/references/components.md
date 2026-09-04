---
name: better-plan-components
description: The exact prop reference for every Better Plan MDX component — names, types, required props, MDX examples, and gotchas, accurate to the implementation. Load before authoring plan components.
---

# Better Plan — Component Reference

Extracted from source at `/src/app/components/*.tsx` and `/src/app/errors/requireProps.tsx`.
This document is ground-truth for skill authoring. Where the existing SKILL.md draft diverges from
the actual code, the discrepancy is flagged under **SKILL.md Discrepancy**.

---

## How `requireProps` works

`requireProps(name, props, required)` returns a `<div class="bp-warning">` React element (not null,
not a throw) when any listed key is `undefined`, `null`, or `""`. The component must check the return
and do `if (warn) return warn;` — missing a required prop renders a labeled warning slot **in place
of the component**. The rest of the page continues to render normally.

---

## 1. `<PlanHeader>`

**File:** `PlanHeader.tsx`

### Props

| Prop | Type | Required | Notes |
|---|---|---|---|
| `title` | `string` | YES | Required via `requireProps` |
| `summary` | `string` | no | One-line sub-heading |
| `status` | `string` | no | Drives `data-status` attr for styling |
| `effort` | `string` | no | Shown in meta strip |
| `author` | `string` | no | Shown in meta strip |
| `risk` | `string` | no | Shown in meta strip |

### Required props

`["title"]` — missing title renders the warning slot instead of the header.

### Status label map (built in)

| Value passed | Displayed text |
|---|---|
| `draft` | Draft |
| `in-review` | In review |
| `approved` | Approved |
| `blocked` | Blocked |
| *(any other string)* | passed string verbatim |

### MDX example

```mdx
<PlanHeader
  title="Realtime collaboration for the editor"
  summary="Add presence, shared cursors, and CRDT merge so two people can edit one doc safely."
  status="in-review"
  effort="~3 weeks"
  author="Claude"
  risk="Medium"
/>
```

### Gotchas

- Use once, first — it is a `<header>` masthead element.
- `status` is a free string; only the four mapped values get semantic labels. Any other string renders verbatim.
- `effort`, `author`, `risk` only render the meta strip if at least one of the three is present.

---

## 2. `<Callout>`

**File:** `Callout.tsx`

### Props

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `"note" \| "tip" \| "warning" \| "danger" \| "success"` | no | Defaults to `"note"` |
| `title` | `string` | no | Bold heading inside the callout |
| `children` | `ReactNode` | no | Body content |

### Required props

None. No call to `requireProps`. The component always renders (worst case: an empty note callout).

### MDX example

```mdx
<Callout type="warning" title="Watch out">
A malformed diagram renders an inline error in its own slot — the rest of the page still renders.
</Callout>
```

### Gotchas

- All five types have inline SVG icons — no emoji, no external deps.
- `type` defaults to `"note"` when omitted.
- The SKILL.md draft says `note (teal) · tip (green) · warning (amber) · danger (red) · success (green check)` — this is consistent with the icon definitions in code, correct as written.

---

## 3. `<Badge>`

**File:** `Badge.tsx`

### Props

| Prop | Type | Required | Notes |
|---|---|---|---|
| `variant` | `"draft" \| "review" \| "approved" \| "blocked" \| "info"` | no | Defaults to `"info"` |
| `children` | `ReactNode` | YES (structural) | The label text |

### Required props

No call to `requireProps`. However `children` is typed non-optional — missing it renders an empty pill.

### MDX example

```mdx
<Badge variant="approved">accepted</Badge>
```

### Gotchas

- `children` is the visible label. It is not passed to `requireProps` but is structurally required for the component to be meaningful.
- Renders as an inline `<span>` with a dot indicator — suitable for use inline in prose.

---

## 4. `<Diagram>`

**File:** `Diagram.tsx`

### Props

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `"flow" \| "sequence" \| "state" \| "er"` | no | Defaults to `"flow"` |
| `caption` | `string` | no | Shown below diagram |
| `children` | `ReactNode` | no | DSL string (alternative to `nodes`/`edges`) |
| `nodes` | `DiagramNode[]` | no | Structured nodes (takes priority over children) |
| `edges` | `DiagramEdge[]` | no | Structured edges (takes priority over children) |

### Sub-types

```ts
interface DiagramNode {
  id: string;
  label: string;
  accent?: boolean;
}

interface DiagramEdge {
  from: string;
  to: string;
  label?: string;
}
```

### Required props

No call to `requireProps`. But if neither children DSL nor nodes/edges produce any edges/nodes, an
inline parse error is shown in the diagram slot.

### DSL rules (children-as-string)

- Each line: `A -> B` — creates two nodes and one edge.
- `A -> B : label` — edge with a label (text after the **last** `:` on the line).
- `A -> B -> C` — chain: three nodes, two edges (label only applies to the last edge in a chain).
- `A[accent]` — marks node A amber. Works inline in any position: `A[accent] -> B`.
- Lines without `->` are **silently skipped** (blank lines, comments, anything else).
- If DSL produces zero nodes AND zero edges, shows error: `'No edges found — DSL must contain at least one "A -> B" arrow.'`

**IMPORTANT:** DSL is passed as a template literal string child, NOT as JSX children. In MDX this means wrapping in `{``...``}`:

```mdx
<Diagram type="flow" caption="Render pipeline">
{`MDX file -> compile -> render [accent] -> localhost`}
</Diagram>
```

### Layout

- Uses `@dagrejs/dagre` for auto-layout.
- `type="flow"` → rankdir `LR` (left-to-right).
- All other types (`sequence`, `state`, `er`) → rankdir `TB` (top-to-bottom).
- Node size is fixed: 120 × 44 px.

### Interaction

- Zoom: mouse wheel (non-passive, prevents page scroll). Buttons: `−` (×0.8), `+` (×1.25), reset (shows current %). Scale range: 0.4×–4×.
- Pan: pointer drag anywhere on viewport.

### Structured props alternative

```mdx
<Diagram type="flow"
  nodes={[{ id: "a", label: "MDX file" }, { id: "c", label: "render", accent: true }]}
  edges={[{ from: "a", to: "c", label: "compile" }]} />
```

When `nodes` or `edges` props are present, children DSL is **ignored entirely**.

### SKILL.md Discrepancy

The minimal plan example in SKILL.md contains:
```mdx
<Diagram type="flow">{`graph LR
  A[Click Export] --> B[serialize rows] --> C[stream file]`}</Diagram>
```
This is **wrong** — it uses Mermaid syntax (`graph LR`, `-->`, `[...]`). The DSL parser only understands `->` arrows and `[accent]` suffix. `graph LR` would be silently skipped (no `->`) and `-->` is not recognized as `->`. This example would render a parse error. The correct DSL would be:
```mdx
<Diagram type="flow">{`Click Export -> serialize rows -> stream file`}</Diagram>
```

---

## 5. `<APISpec>`

**File:** `APISpec.tsx`

### Props

| Prop | Type | Required | Notes |
|---|---|---|---|
| `method` | `"GET" \| "POST" \| "PUT" \| "DELETE"` | YES | HTTP verb |
| `path` | `string` | YES | Endpoint path |
| `summary` | `string` | no | Short description shown in collapsed row |
| `params` | `APIParam[]` | no | Parameter table rows |
| `request` | `string` | no | Raw request body example (rendered in `<pre>`) |
| `response` | `string` | no | Raw response body example (rendered in `<pre>`) |

### Sub-type

```ts
interface APIParam {
  name: string;      // required
  type: string;      // required
  required?: boolean;
  note?: string;
}
```

### Required props

`["method", "path"]` — either missing renders the warning slot.

### MDX example

```mdx
<APISpec
  method="POST"
  path="/v1/plans"
  summary="Render a new plan"
  params={[
    { name: "source", type: "string", required: true, note: "Path to the MDX file" },
    { name: "port",   type: "number", note: "Preferred port; next free chosen if taken" }
  ]}
  request={`{ "source": "./plan.mdx", "port": 4711 }`}
  response={`{ "url": "http://localhost:4711", "sections": 7 }`}
/>
```

### Gotchas

- Renders as a `<details>` element — collapsed by default, showing method + path + summary.
- The body (params table + request/response blocks) only renders if at least one of `params`, `request`, or `response` is present.
- `request` and `response` are plain strings rendered in `<pre><code>` — pass them as template literals for multi-line JSON.
- `method` must be exactly one of the four uppercase strings; no lowercase, no PATCH.

---

## 6. `<AnnotatedCode>`

**File:** `AnnotatedCode.tsx`

### Props

| Prop | Type | Required | Notes |
|---|---|---|---|
| `lang` | `string` | no | Language label (shown as caption, e.g. `"ts"`) |
| `code` | `string` | YES | The code string |
| `annotations` | `AnnotationItem[]` | no | Margin notes; defaults to `[]` |

### Sub-type

```ts
interface AnnotationItem {
  lines: string;   // required — "2" or "2-4"
  tag?: string;    // amber tag chip (e.g. "risk", "live reload")
  note: string;    // required — the annotation text
}
```

### Required props

`["code"]` — missing code renders the warning slot.

### MDX example

```mdx
<AnnotatedCode
  lang="ts"
  code={`async function render(src) {
  const mdx = await compile(src)
  const port = await freePort(4711)
  server.on('change', () => recompile())
  return { url: \`http://localhost:\${port}\` }
}`}
  annotations={[
    { lines: "2",   tag: "risk",        note: "Compile errors must show a located overlay." },
    { lines: "3-4", tag: "live reload", note: "Debounce rapid saves to avoid thrashing." }
  ]}
/>
```

### Gotchas

- `lines` is a **string**, not a number: `"2"` for one line, `"2-4"` for a range. Lines are 1-based.
- Multiple annotations can cover overlapping line ranges — each matched line gets the highlight class.
- The built-in tokenizer covers JS/TS keywords, strings (single/double/backtick), numbers, and `//` comments. It is not a full parser — complex expressions may not highlight perfectly.
- Highlighted lines glow amber; the margin notes appear in a right-hand `<aside>`.
- `lang` is purely decorative — it renders as a caption label, not for syntax highlighting logic.
- The syntax highlighter scans for: keywords (teal), string literals (green), number literals (amber), `//` comments (muted).

---

## 7. `<Wireframe>`

**File:** `Wireframe.tsx`

### Props

| Prop | Type | Required | Notes |
|---|---|---|---|
| `frame` | `"browser" \| "phone"` | no | Defaults to `"browser"` |
| `url` | `string` | no | URL bar text (browser frame only) |
| `children` | `string` | YES | ASCII sketch content |

### Required props

`["children"]` — missing children renders the warning slot.

### MDX example

```mdx
<Wireframe frame="browser" url="app.example.com/editor">
{`[ top bar: logo + actions          ]
 [ sidebar ][ document canvas       ]
 [ status / presence                ]`}
</Wireframe>
```

Phone variant:
```mdx
<Wireframe frame="phone">
{`[ header ]
 [ list item 1 ]
 [ list item 2 ]`}
</Wireframe>
```

### Gotchas

- `children` must be a string — it is rendered in a `<pre>` tag. Pass as a template literal.
- `url` is only rendered for `frame="browser"`; it is silently ignored for `frame="phone"`.
- Phone frame renders a rounded shell with a notch pill.
- Browser frame renders three colored dots + optional URL bar.

---

## 8. `<FileTree>`

**File:** `FileTree.tsx`

### Props

| Prop | Type | Required | Notes |
|---|---|---|---|
| `children` | `string` | YES | Indented text DSL |

### Required props

`["children"]` — missing children renders the warning slot.

### DSL rules

- Each non-blank line is one node.
- Indentation (spaces or tabs, 1 tab = 2 spaces) defines nesting.
- Trailing `/` → folder. Without `/` → file.
- `name # comment text` → the text after ` #` (space + hash) becomes a **muted grey chip**.
- `name <-- chip text` → the text after `<--` becomes an **amber "look here" chip** (with pen icon).
- Both annotations can appear on one line: `name.ts # muted note <-- amber chip`.
- The order of parsing: `<--` chip is extracted first, then `#` comment.
- File extension is auto-detected and shown as a badge. Extensions with color treatment: `ts`, `tsx` (blue-teal), `md`, `mdx` (muted), `html` (orange).
- Folders render with a chevron toggle and are **open by default** (`useState(true)`).

### MDX example

```mdx
<FileTree>
{`better-plan/
  src/
    server.ts        # CLI + live-reload host  <-- edit here
    components/      # one file per plan component
  style.html         # design system  <-- source of truth`}
</FileTree>
```

### Gotchas

- `children` is cast to `string` internally — pass as a template literal.
- Do NOT draw `├─`/`└─` box-drawing characters yourself; the renderer handles visual connectors.
- Folders start expanded. There is no way to set a folder's initial state to collapsed via the DSL.
- Blank lines are skipped by the parser.
- The `# comment` detection requires a **space before the hash** (` #`). A `#` at the start of a name (e.g. `#file`) is NOT a comment.

---

## 9. `<ADR>`

**File:** `ADR.tsx`

### Props

| Prop | Type | Required | Notes |
|---|---|---|---|
| `id` | `string` | no | ADR identifier e.g. `"ADR-001"` |
| `title` | `string` | YES | Decision title |
| `status` | `string` | no | Free string (e.g. `"accepted"`, `"proposed"`, `"superseded"`) |
| `context` | `string` | no | Background paragraph |
| `options` | `string` | no | Alternatives considered |
| `decision` | `string` | no | What was chosen |
| `consequence` | `string` | no | Outcomes / trade-offs |

### Required props

`["title"]` — missing title renders the warning slot.

### MDX example

```mdx
<ADR
  id="ADR-001"
  title="Author plans as MDX, not static HTML"
  status="accepted"
  context="Claude needs prose + components in one file; the reviewer needs live iteration."
  options="Static HTML export · notebook · full SSG · MDX + dev server"
  decision="MDX compiled by a local dev server with live reload."
  consequence="Interactive components are first-class; a static share export is deferred."
/>
```

### Gotchas

- All prose fields (`context`, `options`, `decision`, `consequence`) are plain strings rendered as `<p>` paragraphs — no markdown inside them.
- `status` is a free string; no enum enforcement. The `data-status` attribute is set for CSS targeting.
- The four prose sections always render their label headings (Context, Options, Decision, Consequence) whether or not the field is provided — the value paragraph is conditional.

---

## 10. `<Comparison>`

**File:** `Comparison.tsx`

### Props

| Prop | Type | Required | Notes |
|---|---|---|---|
| `columns` | `string[]` | YES | Column headers |
| `rows` | `ComparisonRow[]` | YES | Table rows |

### Sub-type

```ts
interface ComparisonRow {
  cells: string[];   // required — length should match columns
  win?: boolean;     // marks row as recommended (amber star + aria-label)
}
```

### Required props

`["columns", "rows"]` — either missing renders the warning slot.

### MDX example

```mdx
<Comparison
  columns={["Approach", "Iteration", "Interactivity", "Verdict"]}
  rows={[
    { cells: ["Plain markdown", "n/a", "none", "rejected"] },
    { cells: ["MDX + dev server", "live", "full", "selected"], win: true }
  ]}
/>
```

### Gotchas

- The first cell in each row renders as a `<th scope="row">` (row header), not a `<td>`.
- `win: true` adds a `★` marker before the first cell and sets `aria-label="... — recommended"`.
- `cells` length should match `columns` length; mismatches render without error but produce misaligned cells.
- All cell values are plain strings.

---

## 11. `<Steps>` / `<Step>`

**Files:** `Steps.tsx`

### `<Steps>` Props

| Prop | Type | Required | Notes |
|---|---|---|---|
| `children` | `ReactNode` | no | Should be `<Step>` elements |

No `requireProps` call on `<Steps>`.

### `<Step>` Props

| Prop | Type | Required | Notes |
|---|---|---|---|
| `title` | `string` | YES | Step heading |
| `done` | `boolean` | no | Shows `✓` instead of step number |
| `children` | `ReactNode` | no | Optional body content below title |
| `_index` | `number` | no | **Injected by `<Steps>` — do not pass manually** |

### Required props

`Step`: `["title"]` — missing title renders the warning slot for that step.

### MDX example

```mdx
<Steps>
  <Step title="Write the plan as MDX" done>Claude composes prose + components.</Step>
  <Step title="Invoke the renderer">`better-plan ./plan.mdx` prints a URL.</Step>
  <Step title="Reviewer reads and navigates">Opens the URL; jumps via the section rail.</Step>
</Steps>
```

### Gotchas

- `<Steps>` injects `_index` (1-based) into each `<Step>` child via `Children.map`. Do not set `_index` yourself.
- Only direct `<Step>` children that are valid React elements get numbered. Non-element children pass through unchanged.
- `done` is a boolean prop: `done` or `done={true}` — shows `✓` and the `bp-step-done` class.
- `<Step>` children can contain arbitrary JSX (not just text).

---

## 12. `<Tabs>` / `<Tab>`

**File:** `Tabs.tsx`

### `<Tabs>` Props

| Prop | Type | Required | Notes |
|---|---|---|---|
| `children` | `ReactNode` | no | Should be `<Tab>` elements |

### `<Tab>` Props

| Prop | Type | Required | Notes |
|---|---|---|---|
| `label` | `string` | YES (structural) | Tab button text |
| `children` | `ReactNode` | no | Panel content |

### Required props

No `requireProps` calls. `Tab` itself renders `null` — `Tabs` reads `tab.props.label` and `tab.props.children` directly.

### MDX example

```mdx
<Tabs>
  <Tab label="Overview">A local tool that turns MDX into a navigable plan.</Tab>
  <Tab label="Risks">A polished library must beat prose for comprehension.</Tab>
</Tabs>
```

### Keyboard model

- `ArrowRight` — next tab (wraps).
- `ArrowLeft` — previous tab (wraps).
- `Home` — first tab.
- `End` — last tab.
- Roving `tabIndex`: selected tab has `tabIndex=0`, others have `tabIndex=-1`.
- On selection change, a live region announces `"<label> panel shown"`.

### Gotchas

- `<Tab>` **renders `null`** — it is a data-carrying marker component only. `<Tabs>` reads its props.
- Only children with a string `label` prop are treated as tabs. Other children are silently ignored.
- First tab is selected by default (`useState(0)`).
- `useId()` is used to generate unique ids for ARIA wiring — no manual id management needed.

---

## 13. `<Collapsible>`

**File:** `Collapsible.tsx`

### Props

| Prop | Type | Required | Notes |
|---|---|---|---|
| `summary` | `string` | YES | Always-visible disclosure label |
| `children` | `ReactNode` | no | Hidden body content |

### Required props

`["summary"]` — missing summary renders the warning slot.

### MDX example

```mdx
<Collapsible summary="Advanced: how live reload debounces rapid saves">
On each save the watcher cancels the in-flight recompile and schedules the latest source,
so only the final content of a burst renders.
</Collapsible>
```

### Gotchas

- Implemented as a native `<details>` / `<summary>` element — no React state. Collapse/expand is browser-native.
- Closed by default (no `open` attribute on `<details>`).
- `summary` is a plain string — no JSX inside the `summary` prop.
- `children` can be arbitrary JSX.

---

## 14. `<Stat>`

**File:** `Stat.tsx`

### Props

| Prop | Type | Required | Notes |
|---|---|---|---|
| `value` | `string` | YES | The large displayed number/text |
| `unit` | `string` | no | Unit suffix (smaller, next to value) |
| `label` | `string` | no | Descriptor below the value |
| `delta` | `string` | no | Change pill (e.g. `"+12%"`, `"under 5s target"`) |

### Required props

`["value"]` — missing value renders the warning slot.

### MDX example

```mdx
<Stat value="3.1" unit="s" label="Cold start → URL" delta="under 5s target" />
```

Group multiple stats in a row by placing them adjacent (they are `inline-block` / flex items):

```mdx
<Stat value="99.9" unit="%" label="Uptime" />
<Stat value="12" unit="ms" label="p50 latency" delta="-3ms" />
```

### Gotchas

- All props are strings (even `value` — it is not a number type).
- `delta` is a free string — no automatic positive/negative coloring from the prop itself; CSS handles styling.

---

## 15. `<Checklist>`

**File:** `Checklist.tsx`

### Props

| Prop | Type | Required | Notes |
|---|---|---|---|
| `items` | `ChecklistItem[]` | YES | Array of checklist items |

### Sub-type

```ts
interface ChecklistItem {
  text: string;      // required
  done?: boolean;    // default false
}
```

### Required props

`["items"]` — missing items renders the warning slot.

### MDX example

```mdx
<Checklist items={[
  { text: "All MUST acceptance criteria pass", done: true },
  { text: "Both themes meet WCAG AA contrast" },
  { text: "Live reload fires in under 1s" }
]} />
```

### Gotchas

- `done: true` items show a checkmark glyph and get a `bp-check-done` class (strikethrough styling).
- `done` defaults to `false` — omit it for unchecked items.
- `text` is a plain string — no JSX inside items.
- `key` for each `<li>` is `item.text` — duplicate text values will cause React key warnings.

---

## 16. `<DataModel>` / `<Entity>`

**File:** `DataModel.tsx`

### `<DataModel>` Props

| Prop | Type | Required | Notes |
|---|---|---|---|
| `children` | `ReactNode` | no | Should be `<Entity>` elements |

No `requireProps` on `<DataModel>`.

### `<Entity>` Props

| Prop | Type | Required | Notes |
|---|---|---|---|
| `name` | `string` | YES | Entity/table name (shown as header) |
| `fields` | `FieldDef[]` | no | Field rows; defaults to `[]` |

### Sub-type

```ts
interface FieldDef {
  name: string;      // required
  type: string;      // required
  pk?: boolean;      // primary key — renders amber highlight
}
```

### Required props

`Entity`: `["name"]` — missing name renders the warning slot for that entity.

### MDX example

```mdx
<DataModel>
  <Entity name="Plan" fields={[
    { name: "id",       type: "uuid",      pk: true },
    { name: "title",    type: "string" },
    { name: "sections", type: "Section[]" }
  ]} />
  <Entity name="Section" fields={[
    { name: "id",      type: "uuid", pk: true },
    { name: "heading", type: "string" },
    { name: "planId",  type: "uuid" }
  ]} />
</DataModel>
```

### Gotchas

- `<DataModel>` is just a `<div>` flex container — it adds no behavior, only layout.
- `<Entity>` renders as an HTML `<table>` with `aria-label={name}`.
- `pk: true` fields get the `bp-entity-pk` class (amber highlight in the row).
- `fields` defaults to `[]` — an entity with no fields renders just the name header.

---

## 17. `<Timeline>`

**File:** `Timeline.tsx`

### Props

| Prop | Type | Required | Notes |
|---|---|---|---|
| `items` | `TimelineItem[]` | YES | Ordered list of phases |

### Sub-type

```ts
interface TimelineItem {
  phase: string;     // required — short phase label
  title: string;     // required — what happens in this phase
  when?: string;     // optional date/duration label (left column)
  accent?: boolean;  // milestone — renders amber dot + "★ milestone" tag
}
```

### Required props

`["items"]` — missing items renders the warning slot.

### MDX example

```mdx
<Timeline items={[
  { phase: "Phase 1", title: "Renderer + server",   when: "Week 1" },
  { phase: "Phase 2", title: "Component library",   when: "Weeks 2-3" },
  { phase: "Launch",  title: "Ship to reviewers",   when: "Week 4", accent: true }
]} />
```

### Gotchas

- `accent: true` renders the dot in amber and appends `" ★ milestone"` to the phase label.
- `when` is a free string shown in the left column. When omitted, the column renders empty (not hidden).
- The component renders as an `<ol>` with `aria-label="Timeline"`.
- Key is `${phase}-${title}` — duplicate phase+title combos cause React key warnings.

---

## SKILL.md Discrepancy Summary

| Location | Claimed in SKILL.md | Actual code behavior |
|---|---|---|
| Minimal plan `<Diagram>` example | Uses Mermaid syntax: `graph LR`, `-->`, `[Label]` | **WRONG.** The DSL only recognizes `->` arrows and `[accent]` suffix. Mermaid syntax is silently skipped, resulting in a parse error. |
| `<Collapsible>` description | "summary (required) is the always-visible label" | Correct — `requireProps` enforces `["summary"]`. |
| `<Callout>` — no required props stated | Consistent with code (no `requireProps` call). | Correct. |
| `<Diagram>` — structured props example | `accent: true` as a node property | Correct — matches `DiagramNode.accent?: boolean`. |
| `<ADR>` status examples | "proposed \| accepted \| superseded" | These are just examples; status is a free string — consistent with code. |
| `<Timeline>` | No mention of `accent` flag rendering `"★ milestone"` text | Missing from SKILL.md — `accent: true` adds `" ★ milestone"` to phase label in the rendered output. |
| `<FileTree>` | Mentions "# comment → muted chip" and "<-- chip → amber chip" | Correct. Also note `#` detection requires a space before the hash (` #`). |
| `<Steps>` / `<Step>` `done` prop | `done` shown as boolean attribute | Correct — `done` is `boolean`, works as bare attribute or `done={true}`. |
