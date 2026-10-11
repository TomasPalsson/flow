# The smoothbrain page

One HTML file. When you publish it as an Artifact, `artifact-design` wins on the document shell: leave out `<!doctype>`, `<html>`, `<head>` and `<body>` tags and keep the `<title>`, `<style>` and body content. A local file that is not published keeps the full shell shown below. The five rungs of the zoom ladder are `<section data-zoom="...">` elements, in this order. `scripts/check.mjs` finds them by these attributes, so keep the names exact.

| `data-zoom` | Holds | Check |
|---|---|---|
| `big-picture` | `<h1>`, one sentence in `<p class="one-line">`, a wide and a tall inline `<svg>` | SVG present, sentence ≤ 25 words |
| `parts` | 3 to 5 `<article class="part">`, each with a small SVG, an `<h3>` noun, one line | count 3..5 |
| `moves` | a stage SVG plus 3 or more `[data-step]` captions, Back/Next buttons | ≥ 3 steps |
| `detail` | one or more `<details>` with `<summary>` | ≥ 1 |
| `words` | `<dl>` of `<dt>` term + `<dd>` (icon + one line) | every term also used on the page |

Optional: `data-zoom="breaks"` (where the comparison stops being true) and `data-zoom="check"` (questions in `<details>`). They go after `moves` and before `detail`.

## Skeleton

```html
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>How Hooks Stop</title>
<style>
:root{--bg:#fbfaf7;--ink:#1d1b18;--muted:#6b665e;--line:#d9d4ca;--a:#d2552b;--b:#2b6cb0;--c:#2f855a;--card:#fff}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#15140f;--ink:#f1ede4;--muted:#a49d90;--line:#3a372f;--a:#f08a5d;--b:#7fb3ec;--c:#79c99a;--card:#1f1d18}}
:root[data-theme="dark"]{--bg:#15140f;--ink:#f1ede4;--muted:#a49d90;--line:#3a372f;--a:#f08a5d;--b:#7fb3ec;--c:#79c99a;--card:#1f1d18}
body{margin:0;background:var(--bg);color:var(--ink);font:18px/1.55 system-ui,sans-serif}
section{max-width:68rem;margin:0 auto;padding:3rem 16px}
[data-zoom="big-picture"]{display:grid;gap:1rem;padding-top:2rem}
[data-zoom="big-picture"] svg{width:100%;max-height:62vh}
.one-line{font-size:clamp(1.3rem,3vw,1.9rem);max-width:36ch;margin:0}
.parts{display:grid;gap:1rem;grid-template-columns:repeat(auto-fit,minmax(14rem,1fr))}
.part{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:1rem}
.js [data-step]{display:none}.js [data-step].on{display:block}
@media (max-width:640px){[data-zoom="moves"]{display:flex;flex-direction:column}[data-zoom="moves"] > h2,[data-zoom="moves"] > p:not(.controls){order:-2}[data-zoom="moves"] .steps,[data-zoom="moves"] .controls{order:-1}}
@media (prefers-reduced-motion:reduce){*{transition:none!important;animation:none!important}}
</style>
</head>
<body>
<section data-zoom="big-picture">…</section>
<section data-zoom="parts"><div class="parts"><article class="part">…</article></div></section>
<section data-zoom="moves">…</section>
<section data-zoom="detail">…</section>
<section data-zoom="words"><dl>…</dl></section>
<script>/* step-through */</script>
</body>
</html>
```

Pick the palette and fonts for the topic. The tokens above are a shape, not a look. Colour carries meaning: one colour per kind of part, the same on every picture.

## Big picture SVG

- Draw two SVGs by default: a wide one (`viewBox` around `0 0 1000 560`) and a tall one for phones (`viewBox` width 400 to 600), and switch with a CSS media query at 640px. One 1000-wide SVG shows at 0.375 scale on a 375px phone, so it would need 30-unit labels. Give it `role="img"`, a `<title>` and a `<desc>` that says the one sentence.
- Every part of the whole is drawn and labelled with `<text>` on or beside the shape. No legend.
- Arrows show what causes what. Write the verb on the arrow ("sends", "checks", "stops").
- Use `fill="var(--a)"` or `stroke="currentColor"` so it works in dark mode.
- At phone width the rendered text must stay ≥ 11px. Rendered size = font size × screen width ÷ viewBox width, so 22px text in a 600-wide viewBox shows at about 13px on a 375px phone. Use fewer, bigger labels. If that is not enough, draw a second, taller SVG (viewBox width 400 to 600) and switch between the two with a CSS media query. The same rule applies to the step-through stage.

## How it moves (step-through)

One stage SVG stays still. Each step lights up the parts that act in that step (`data-on="id id"`) and shows one caption. Each step is one event. One event may change several values (a clock, a state, a bill); that is fine.

Without JavaScript, every caption shows as a plain list (the `.js` class gates the hiding). The caption list is `aria-live="polite"` so a screen reader hears each step. On a phone the captions and buttons sit above the stage, so the reader does not scroll after each Next.

```html
<section data-zoom="moves">
  <h2>How it moves</h2>
  <svg id="stage" viewBox="0 0 1000 400" role="img"><title>…</title>
    <g id="s-user">…</g><g id="s-hook">…</g><g id="s-model">…</g>
  </svg>
  <ol class="steps" aria-live="polite">
    <li data-step data-on="s-user" data-v-state="waiting">You type <b>/goal</b>.</li>
    <li data-step data-on="s-user s-hook" data-v-state="saved">The <b>hook</b> (a script that runs at a fixed moment) saves the goal.</li>
    <li data-step data-on="s-hook s-model" data-v-state="blocked">…</li>
  </ol>
  <p class="controls"><button id="back">Back</button> <span id="count"></span> <button id="next">Next</button></p>
</section>
<script>
document.documentElement.classList.add('js');
const steps=[...document.querySelectorAll('[data-step]')];let i=0;
function show(n){i=Math.max(0,Math.min(steps.length-1,n));
  steps.forEach((s,k)=>s.classList.toggle('on',k===i));
  const on=(steps[i].dataset.on||'').split(' ');
  document.querySelectorAll('#stage > g[id]').forEach(g=>g.style.opacity=on.includes(g.id)?1:.18);
  // data-v-<id>="text" on a step writes that text into the stage element #v-<id>.
  for(const [k,v] of Object.entries(steps[i].dataset)) if(k.startsWith('v')&&k!=='v'){
    const el=document.getElementById('v-'+k.slice(1).replace(/[A-Z]/g,c=>'-'+c.toLowerCase()).replace(/^-/,'')); if(el) el.textContent=v;}
  document.getElementById('count').textContent=`${i+1} / ${steps.length}`;}
document.getElementById('next').onclick=()=>show(i+1);
document.getElementById('back').onclick=()=>show(i-1);
document.addEventListener('keydown',e=>{if(e.key==='ArrowRight')show(i+1);if(e.key==='ArrowLeft')show(i-1)});
show(0);
</script>
```

When a value changes (a counter, a queue length, a state name), draw it in the stage as `<text id="v-state">` and set `data-v-state="…"` on each step. The script writes it. Put every `data-v-*` value on every step, not only the ones that change, so Back restores the stage. The reader must see the real numbers move.

## Gap marking (optional, 3 or more part cards)

Each part card gets a three-way toggle: know, fuzzy, lost. A box under the cards shows the request for the next pass, built from the cards marked fuzzy or lost. The box is a readonly `<textarea>` that is always visible, so the reader can select the text by hand when a sandboxed frame blocks the clipboard. The copy button tries the clipboard and falls back to selecting the textarea.

```html
<article class="part"><h3>queue</h3><p>Holds jobs.</p>
  <p role="group" aria-label="How well do you know queue?">
    <button data-mark="know" aria-pressed="false">know</button>
    <button data-mark="fuzzy" aria-pressed="false">fuzzy</button>
    <button data-mark="lost" aria-pressed="false">lost</button></p></article>
<!-- after the cards, inside the parts section -->
<p><label for="gap">Ask about the gaps</label></p>
<textarea id="gap" readonly rows="3" data-gap-request>Mark the parts that are fuzzy or lost.</textarea>
<button id="copy">Copy</button>
<script>
const gap=document.getElementById('gap'),state={};
document.querySelectorAll('.part [data-mark]').forEach(b=>b.onclick=()=>{
  const card=b.closest('.part'),name=card.querySelector('h3').textContent;
  state[name]=b.dataset.mark;
  card.querySelectorAll('[data-mark]').forEach(x=>x.setAttribute('aria-pressed',x===b));
  const open=Object.keys(state).filter(k=>state[k]!=='know');
  gap.value=open.length?'Explain deeper: '+open.join(', '):'Mark the parts that are fuzzy or lost.';});
document.getElementById('copy').onclick=()=>{
  const sel=()=>{gap.focus();gap.select()};
  (navigator.clipboard?navigator.clipboard.writeText(gap.value):Promise.reject()).catch(sel);};
</script>
```

`scripts/check.mjs` warns when `[data-mark]` toggles exist without a `[data-gap-request]` textarea.

## Inline scripts

Every inline `<script>` must parse. The browser ends a script at the first `</script>`, even inside a string, so code or HTML you quote in the page can cut the script short; escape `<` as `\u003c` in data and code strings embedded in a script, or write `<\/script>`. `scripts/check.mjs` parses each inline script and each `type="application/json"` script and fails with the line number.

## Detail

```html
<details><summary>Why the hook can refuse to stop</summary>
  <p>The Stop hook returns <code>{"decision":"block"}</code> … (<code>hooks/stop.sh:42</code>)</p>
</details>
```

Detail is for depth, not for the main story. Each section answers one question, named in the summary.

## Words card

```html
<section data-zoom="words"><h2>Words on this page</h2>
<dl>
  <div><dt>hook</dt><dd><svg class="ico">…</svg> A script that Claude Code runs at a fixed moment.</dd></div>
</dl></section>
```

The `<dt>` text must match a word on the page (case does not matter; a plural with -s or -es counts). If the page says "Stop hook" in one place and "end hook" in another, pick one.

## What the checker reads

- Sentences and acronyms: visible prose only. SVG text, `<code>` and `<pre>` are skipped. Explain any acronym in a drawing in the words card or in nearby prose.
- Words-card terms: visible text including `<code>`, so `TASKS.md` in code counts as a use.
- File names (`TASKS.md`) and IDs (`CHK011`) are not acronyms. Other all-caps words (status names such as `FAIL`, `HIT`) count as acronyms: put them in `<code>`.
- Step captions (`[data-step]`): 20 words max per sentence. Other prose: 25.
- The acronym check uses reading order, labels and eyebrows above the `<h1>` included. Spell the acronym out at its first appearance, wherever that is.

## Failure modes to check by eye

- Decoration over mechanism: a pretty picture that does not show how the thing works.
- An analogy used past the point where it holds.
- A hard word explained with another hard word.
- A wall of text: more than 6 sentences in a paragraph.
- A flat page: every section the same weight, no big picture.
- A control that changes nothing the reader needs to see.
- Invented facts: every claim about code must trace to a file you read.
