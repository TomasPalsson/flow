# The smoothbrain page

One HTML file. The five rungs of the zoom ladder are `<section data-zoom="...">` elements, in this order. `scripts/check.mjs` finds them by these attributes, so keep the names exact.

| `data-zoom` | Holds | Check |
|---|---|---|
| `big-picture` | `<h1>`, one sentence in `<p class="one-line">`, one inline `<svg>` | SVG present, sentence ≤ 25 words |
| `parts` | 3 to 5 `<article class="part">`, each with a small SVG, an `<h3>` noun, one line | count 3..5 |
| `moves` | a stage SVG plus 3 or more `[data-step]` captions, Back/Next buttons | ≥ 3 steps |
| `detail` | one or more `<details>` with `<summary>` | ≥ 1 |
| `words` | `<dl>` of `<dt>` term + `<dd>` (icon + one line) | every term also used on the page |

Optional: `data-zoom="breaks"` (where the comparison stops being true) and `data-zoom="check"` (questions in `<details>`). They go after `moves`.

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
[data-zoom="big-picture"]{min-height:92vh;display:grid;align-content:center;gap:1rem}
[data-zoom="big-picture"] svg{width:100%;max-height:62vh}
.one-line{font-size:clamp(1.3rem,3vw,1.9rem);max-width:36ch;margin:0}
.parts{display:grid;gap:1rem;grid-template-columns:repeat(auto-fit,minmax(14rem,1fr))}
.part{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:1rem}
[data-step]{display:none}[data-step].on{display:block}
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

- One `viewBox`, around `0 0 1000 560`. Give it `role="img"`, a `<title>` and a `<desc>` that says the one sentence.
- Every part of the whole is drawn and labelled with `<text>` on or beside the shape. No legend.
- Arrows show what causes what. Write the verb on the arrow ("sends", "checks", "stops").
- Use `fill="var(--a)"` or `stroke="currentColor"` so it works in dark mode.
- At phone width the text must stay ≥ 12px. Use fewer, bigger labels. If that is not enough, draw a second, taller SVG and switch between the two with a CSS media query.

## How it moves (step-through)

One stage SVG stays still. Each step lights up the parts that act in that step (`data-on="id id"`) and shows one caption. Each step changes only one thing.

```html
<section data-zoom="moves">
  <h2>How it moves</h2>
  <svg id="stage" viewBox="0 0 1000 400" role="img"><title>…</title>
    <g id="s-user">…</g><g id="s-hook">…</g><g id="s-model">…</g>
  </svg>
  <ol class="steps">
    <li data-step data-on="s-user">You type <b>/goal</b>.</li>
    <li data-step data-on="s-user s-hook">The <b>hook</b> (a script that runs at a fixed moment) saves the goal.</li>
    <li data-step data-on="s-hook s-model">…</li>
  </ol>
  <button id="back">Back</button> <span id="count"></span> <button id="next">Next</button>
</section>
<script>
const steps=[...document.querySelectorAll('[data-step]')];let i=0;
function show(n){i=Math.max(0,Math.min(steps.length-1,n));
  steps.forEach((s,k)=>s.classList.toggle('on',k===i));
  const on=(steps[i].dataset.on||'').split(' ');
  document.querySelectorAll('#stage > g[id]').forEach(g=>g.style.opacity=on.includes(g.id)?1:.18);
  document.getElementById('count').textContent=`${i+1} / ${steps.length}`;}
document.getElementById('next').onclick=()=>show(i+1);
document.getElementById('back').onclick=()=>show(i-1);
document.addEventListener('keydown',e=>{if(e.key==='ArrowRight')show(i+1);if(e.key==='ArrowLeft')show(i-1)});
show(0);
</script>
```

When a value changes (a counter, a queue length, a state name), draw the value in the stage and change its text per step. The reader must see the real numbers move.

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

The `<dt>` text must match the word on the page exactly (case does not matter). If the page says "Stop hook" in one place and "end hook" in another, pick one.

## Failure modes to check by eye

- Decoration over mechanism: a pretty picture that does not show how the thing works.
- An analogy used past the point where it holds.
- A hard word explained with another hard word.
- A wall of text: more than 6 sentences in a paragraph.
- A flat page: every section the same weight, no big picture.
- A control that changes nothing the reader needs to see.
- Invented facts: every claim about code must trace to a file you read.
