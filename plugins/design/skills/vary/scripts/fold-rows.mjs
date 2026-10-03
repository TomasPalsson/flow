// fold-rows.mjs — turns the measured first-viewport numbers (fold-check.mjs) into PASS / FAIL / INFO rows, gated by treatment.
// Thresholds calibrated on ara-bar/1, hitataekni/1,/4 (scene; must pass) and the nine trial-3 builds.
const TH = { span: 0.95, edge: 0.03, range: 90, steps: 5, plateW: 0.35, plateH: 280, plateSteps: 3, solid: 0.06 };
const BLOCKING_BASE = ['collisions', 'clipped-text', 'hidden-content', 'stray-overlay', 'page-overflow', 'meta-copy', 'duplicate-content', 'headline-on-fold', 'title-on-fold'];

export function blockingRegex(g) {
  return new RegExp(`^(${[...BLOCKING_BASE, ...(g.inScene ? ['headline-in-scene'] : [])].join('|')})`);
}

function coverageRows(c) {
  const { row, d, p, g, inf } = c;
  const cov = (v, min) => `${v.toFixed(2)} (need >= ${min})`;
  const [md, mp] = g.cov || [0.55, 0.45];
  row(g.cov ? d.coverage >= md : null, 'coverage-desktop', cov(d.coverage, md) + inf(g.cov));
  row(g.cov ? p.coverage >= mp : null, 'coverage-phone', cov(p.coverage, mp) + inf(g.cov));
  const rasterOk = d.rasterCoverage >= 0.15, need = g.detail ?? 50;
  row(g.detail != null ? d.detail >= need || rasterOk : null, 'detail', `${d.detail} shape elements in the desktop hero (need >= ${need}); phone ${p.detail}` + (d.detail < need && rasterOk ? `; passes on raster art covering ${d.rasterCoverage.toFixed(2)} of the viewport (canvas/img/video detail is not countable, judge it by eye)` : '') + inf(g.detail != null));
  row(g.inScene ? d.hasH1 && d.overlap : null, 'headline-in-scene', (!d.hasH1 ? 'no h1 found' : d.overlap ? 'h1 box overlaps an art box' : 'h1 sits clear of every art box (floated beside the picture)') + inf(g.inScene));
  row(g.plates != null ? d.plates >= g.plates : null, 'plates', `${d.plates} svg/canvas plates >= 400px wide down the page, hero included (need >= ${g.plates ?? 4})` + inf(g.plates != null));
}

function collisionRows(c) {
  const { row, d, p, g, inf } = c;
  for (const [name, v] of [['desktop', d], ['phone', p]]) {
    const hits = v.text.hits;
    row(hits.length === 0, `collisions-${name}`, hits.length ? hits.slice(0, 6).map(h => `"${h.a}" vs "${h.b}" (${h.why})`).join('; ') : `${v.text.texts} text boxes, none overlapping or covered`);
  }
  const dz = d.dead;
  row(g.dead != null ? dz.frac <= g.dead : null, 'dead-zone', `largest near-uniform rectangle ${dz.w}x${dz.h}px at (${dz.x},${dz.y}) = ${(dz.frac * 100).toFixed(1)}% of the desktop fold (need <= ${(g.dead ?? 0.2) * 100}%)` + inf(g.dead != null));
}

function artRows(c) {
  const { row, d, p, g, inf } = c;
  for (const [name, v] of [['desktop', d], ['phone', p]]) {
    const glass = v.cards.map(x => `"${x.text}" (${x.why}) over ${x.art}`);
    const solid = v.depth.solid.map(x => `"${x.text}" (solid card covering ${(x.share * 100).toFixed(0)}% of the hero art, need <= ${TH.solid * 100}%)`);
    const hits = g.card === 'all' ? [...glass, ...solid] : glass;
    row(g.card ? hits.length === 0 : null, `card-over-art-${name}`, hits.length ? hits.slice(0, 4).join('; ') : 'no translucent, blurred or solid text card over hero art' + inf(g.card));
  }
  for (const [name, v] of [['desktop', d], ['phone', p]]) {
    const f = v.depth.frame, vw = name === 'desktop' ? 1440 : 390;
    const ok = !f.none && f.span >= TH.span && f.left <= TH.edge * vw && f.right <= TH.edge * vw;
    row(g.bleed ? ok : null, `full-bleed-${name}`, (f.none ? 'no hero art box' : `hero art box spans ${(f.span * 100).toFixed(0)}% of the viewport width, margins left ${f.left}px right ${f.right}px (need span >= ${TH.span * 100}% and margins <= ${TH.edge * 100}% of the width)${ok || !g.bleed ? '' : '; a framed picture, not a full-bleed scene'}`) + inf(g.bleed));
  }
  const hs = d.depth.hero;
  row(g.depth ? hs.range >= TH.range && hs.steps >= TH.steps : null, 'rendering-depth', `desktop art area: value range ${hs.range} (need >= ${TH.range}), ${hs.steps} value steps (need >= ${TH.steps}), flat-block texture ${hs.texture.toFixed(2)} (reported, not gated: a smooth gradient sky is legitimately flat)` + inf(g.depth));
}

function plateRows(c) {
  const { row, d, g, inf } = c;
  const share = g.platesSize ?? 0.5, pls = d.depth.plates;
  const small = pls.filter(pl => pl.w < TH.plateW * pl.secW || pl.h < TH.plateH || pl.stats.steps < TH.plateSteps);
  row(g.platesSize != null ? !pls.length || small.length <= pls.length * (1 - share) : null, 'plates-size', (pls.length
    ? `${pls.length - small.length}/${pls.length} section plates >= ${TH.plateW * 100}% of the section width, >= ${TH.plateH}px tall, >= ${TH.plateSteps} value steps (need >= ${share * 100}% of them); failing: ${small.map(pl => `${pl.name} ${pl.w}x${pl.h} of ${pl.secW}px, ${pl.stats.steps} steps`).join(', ') || 'none'}`
    : 'no section plates below the fold') + inf(g.platesSize != null));
  const below = d.sections.filter(s => s.below && !s.excluded), withPlate = below.filter(s => s.plate);
  const frac = below.length ? withPlate.length / below.length : 1, need = g.artDown ?? 0.6;
  row(g.artDown != null ? frac >= need : null, 'art-down-page', (below.length
    ? `${withPlate.length}/${below.length} sections below the fold carry a plate >= 40% of their width (need >= ${need * 100}%); without: ${below.filter(s => !s.plate).map(s => `${s.name}@${s.top}`).join(', ') || 'none'}`
    : 'no sections >= 300px below the fold') + inf(g.artDown != null));
}

function contentRows(c) {
  const { row, d, mode, treatment } = c;
  const dp = d.content.dup, ex = dp.exempt || {};
  const dups = [...dp.text.map(t => `"${t.text}" appears ${t.n}x`), ...dp.prices.map(t => `price list ${t.amounts.join('/')} repeats in <${t.a}> and <${t.b}>`)];
  const applied = Object.entries({ 'pre/code/kbd': ex.code, '[data-repeat-ok]': ex.repeatOk, 'amount blocks in <form>': ex.form }).filter(([, n]) => n).map(([k, n]) => `${n} in ${k}`);
  row(dups.length === 0, 'duplicate-content', (dups.length ? dups.slice(0, 4).join('; ') : 'no text block >= 40 chars or price list repeated outside the footer') + (applied.length ? ` (exemptions applied: ${applied.join(', ')})` : ''));
  const hd = d.content.head, lead = mode === 'persuade' || mode === 'experience';
  row(lead ? !!hd.h1 && !!hd.line && !!hd.action : null, 'headline-on-fold', !hd.h1 ? 'no visible h1 in the first desktop viewport (paint the lettering as a real HTML h1 positioned over the sign/board area; svg text alone does not count)' : !hd.line ? `h1 "${hd.h1}" has no other text line within 200px (no value proposition)` : !hd.action ? `h1 "${hd.h1}" has no link or button with visible text in the first desktop viewport (no primary action)` : `h1 "${hd.h1}" with line "${hd.line}" and action "${hd.action}"` + (lead ? '' : ` (informational in ${mode} mode)`));
  if (!lead) row(!!hd.h1, 'title-on-fold', hd.h1 ? `visible title "${hd.h1}" in the first desktop viewport (treatment ${treatment})` : 'no visible h1 or [role=heading][aria-level=1] in the first desktop viewport (operate/read pages need a page title)');
}

function craftRows(c) {
  const { row, d, p } = c;
  for (const [name, v] of [['desktop', d], ['phone', p]]) {
    const h = v.craft.hidden, o = v.craft.overlay, k = v.craft.clipped;
    row(h.length === 0, `hidden-content-${name}`, h.length ? h.slice(0, 4).map(x => `${x.el} ${x.why}${x.text ? ` "${x.text}"` : ''}`).join('; ') : 'no text or hero art left at opacity 0 / visibility hidden after scrolling');
    row(o.length === 0, `stray-overlay-${name}`, o.length ? o.slice(0, 3).map(x => `${x.el} covers the viewport with a dark fill at alpha ${x.alpha.toFixed ? x.alpha.toFixed(2) : x.alpha}`).join('; ') : 'no viewport-sized semi-opaque dark layer');
    row(k.length === 0, `clipped-text-${name}`, k.length ? k.slice(0, 4).map(x => `"${x.text}" (${x.why})`).join('; ') : 'no text clipped by its box or svg viewport');
  }
}

function pageRows(c) {
  const { row, d, p } = c;
  for (const [name, v] of [['desktop', d], ['phone', p]]) {
    const o = v.pageRows.overflow, m = v.pageRows.meta, sideways = o.scrollWidth > o.vw + 1;
    row(!sideways && o.offenders.length === 0, `page-overflow-${name}`, sideways || o.offenders.length
      ? `${sideways ? `page scrolls sideways (scrollWidth ${o.scrollWidth} > ${o.vw}); ` : ''}${o.offenders.map(x => `${x.el} '${x.text}' right=${x.right}`).join('; ') || 'no single element found (look for negative margins, transforms or an overflowing pseudo-element)'}`
      : `no horizontal overflow (scrollWidth ${o.scrollWidth}, viewport ${o.vw}) and no element crossing the edge outside a scroller`);
    row(m.length === 0, `meta-copy-${name}`, m.length ? m.slice(0, 5).map(x => `"${x.term}" in "...${x.context}..." (designer/scaffold language in visible copy; [data-meta-ok] exempts a subtree)`).join('; ') : 'no designer or scaffold language in the visible text');
  }
}

export function buildRows(res, mode, treatment, g) {
  const lines = [];
  const row = (ok, id, text) => lines.push({ ok, text: `[${ok === null ? 'INFO' : ok ? 'PASS' : 'FAIL'}] ${id}: ${text}` });
  const inf = on => (on ? '' : ` (informational for treatment ${treatment})`);
  const c = { row, d: res.desktop, p: res.phone, g, inf, mode, treatment };
  coverageRows(c); collisionRows(c); artRows(c); plateRows(c); contentRows(c); craftRows(c); pageRows(c);
  return lines;
}
