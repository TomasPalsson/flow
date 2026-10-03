// fold-craft.browser.js — craft-bug measures fold-check.mjs injects into the page (page.addScriptTag), then calls as
// await window.__foldCraft.hidden() / .overlay() / .clipped(). Browser-side only: no imports.
//   hidden   (G1) after load + a scroll through the page: elements with text whose effective opacity is 0 or visibility hidden,
//            or a hero art box (>= 8% of the viewport) that is fully transparent
//   overlay  (G2) a fixed/absolute element covering >= 80% of the viewport with a semi-opaque dark background over the hero
//   clipped  (G3) text whose scrollWidth > clientWidth with overflow hidden, or svg <text> whose bbox crosses its svg viewport
(() => {
  const norm = s => (s || '').replace(/\s+/g, ' ').trim();
  const ownText = el => norm([...el.childNodes].filter(n => n.nodeType === 3).map(n => n.nodeValue).join(' '));
  const label = el => `<${el.tagName.toLowerCase()}${el.id ? '#' + el.id : ''}${typeof el.className === 'string' && el.className ? '.' + el.className.trim().split(/\s+/)[0] : ''}>`;
  const wait = ms => new Promise(r => setTimeout(r, ms));
  // effective opacity along the ancestor chain; gone when display:none (deliberately not rendered)
  const state = el => {
    let op = 1, vis = true;
    for (let n = el; n && n.nodeType === 1; n = n.parentElement) {
      const s = getComputedStyle(n);
      if (s.display === 'none') return { gone: true };
      op *= +s.opacity;
      if (n === el && s.visibility === 'hidden') vis = false;
    }
    return { gone: false, op, vis };
  };
  // content that is meant to stay hidden until opened: menus, dialogs, tooltips, sr-only text, drawers
  const PARKED = '[hidden],dialog,[role="dialog"],[role="menu"],[role="tooltip"],[class*="sr-only"],[class*="visually-hidden"],[class*="menu"],[class*="drawer"],[class*="modal"],[class*="tooltip"],[class*="skip"]';
  // Walk the page in steps; an element is hidden only if it sat in the viewport at some step and never showed at any step
  // (scroll-linked and reveal-on-scroll content shows when it is reached; a reveal that never fires does not).
  const hidden = async () => {
    const seen = new Map(), heroMin = 0.08 * innerWidth * innerHeight, h = document.documentElement.scrollHeight;
    const sample = () => {
      for (const el of document.querySelectorAll('body *')) {
        if (el.closest('defs,template,noscript,' + PARKED) || /^(script|style|title|desc)$/i.test(el.tagName)) continue;
        if (el.closest('svg') && !/^(svg|text|tspan)$/i.test(el.tagName)) continue;
        const r = el.getBoundingClientRect();
        if (!r.width || !r.height || r.right <= 0 || r.left >= innerWidth || r.bottom <= 0 || r.top >= innerHeight) continue;
        const st = state(el); if (st.gone) continue;
        const text = ownText(el), art = /^(svg|canvas|img|video)$/i.test(el.tagName) && !(el.parentElement && el.parentElement.closest('svg'))
          && r.top + scrollY < innerHeight && r.width * r.height >= heroMin;
        if (text.length < 2 && !art) continue;
        const rec = seen.get(el) || { el, text: text.length >= 2 ? text : '', art: art && text.length < 2, shown: false, why: '' };
        if (st.op > 0 && st.vis) rec.shown = true; else rec.why = st.vis ? 'opacity 0' : 'visibility hidden';
        seen.set(el, rec);
      }
    };
    for (let y = 0; y < h; y += Math.max(200, innerHeight * 0.4)) { scrollTo({ top: y, left: 0, behavior: 'instant' }); await wait(150); sample(); }
    scrollTo({ top: 0, left: 0, behavior: 'instant' });
    await wait(3000); // staggered reveals (transition-delay) finish; then re-read every element that was in view and still not shown
    for (const r of seen.values()) { if (r.shown) continue; const st = state(r.el); if (!st.gone && st.op > 0 && st.vis) r.shown = true; }
    return [...seen.values()].filter(r => !r.shown).map(r => ({ el: label(r.el), why: r.art ? 'hero art box fully transparent' : r.why, text: r.text.slice(0, 40) }));
  };
  const rgba = c => { const m = (c || '').match(/rgba?\(([^)]+)\)/); if (!m) return null; const p = m[1].split(/[,/ ]+/).filter(Boolean).map(parseFloat); return { r: p[0], g: p[1], b: p[2], a: p.length > 3 ? p[3] : 1 }; };
  const darkAlpha = cs => {
    const cols = [rgba(cs.backgroundColor), ...[...(cs.backgroundImage || '').matchAll(/rgba?\([^)]+\)/g)].map(m => rgba(m[0]))].filter(Boolean);
    const bad = cols.filter(c => c.a >= 0.05 && c.a < 0.98 && (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) / 255 < 0.35);
    return bad.length ? Math.max(...bad.map(c => c.a)) : 0;
  };
  const covers = r => {
    const w = Math.min(r.right, innerWidth) - Math.max(r.left, 0), h = Math.min(r.bottom, innerHeight) - Math.max(r.top, 0);
    return w > 0 && h > 0 && w * h >= 0.8 * innerWidth * innerHeight;
  };
  // a dark, semi-opaque svg shape covering the viewport, painted after every other shape of its svg (a "grain" rect whose
  // filter composites over a default-black SourceGraphic is the classic case)
  const svgOverlays = () => {
    const out = [], SH = 'path,circle,rect,polygon,ellipse,line,polyline,image,use,text';
    for (const el of document.querySelectorAll('svg rect,svg path,svg polygon')) {
      if (el.closest('defs,symbol,clipPath,mask,pattern,marker,filter,template')) continue;
      const cs = getComputedStyle(el), st = state(el);
      if (st.gone || !st.vis || !/^rgb/.test(cs.fill)) continue;
      const fill = rgba(cs.fill); if (!fill) continue;
      const a = st.op * (+cs.fillOpacity) * fill.a;
      if (a < 0.2 || a >= 0.98 || (0.2126 * fill.r + 0.7152 * fill.g + 0.0722 * fill.b) / 255 >= 0.35) continue;
      if (!covers(el.getBoundingClientRect())) continue;
      const svg = el.ownerSVGElement;
      const later = [...svg.querySelectorAll(SH)].filter(s => !s.closest('defs,symbol,clipPath,mask,pattern,marker,filter') && (el.compareDocumentPosition(s) & Node.DOCUMENT_POSITION_FOLLOWING) && !el.contains(s));
      if (!later.length) out.push({ el: label(el) + ' in svg', alpha: +a.toFixed(2) });
    }
    return out;
  };
  const overlay = () => {
    scrollTo({ top: 0, left: 0, behavior: 'instant' });
    const hits = svgOverlays();
    for (const el of document.querySelectorAll('body *')) {
      if (el.closest('svg,defs,template') || /^(script|style|noscript)$/i.test(el.tagName)) continue;
      const cs = getComputedStyle(el);
      if (cs.display === 'none' || cs.visibility === 'hidden' || +cs.opacity === 0) continue;
      const rect = el.getBoundingClientRect();
      if (/^(fixed|absolute)$/.test(cs.position) && covers(rect)) {
        const a = darkAlpha(cs); if (a) hits.push({ el: label(el), alpha: a });
      }
      for (const ps of ['::before', '::after']) {
        const pc = getComputedStyle(el, ps);
        if (pc.content === 'none' || pc.display === 'none' || !/^(fixed|absolute)$/.test(pc.position)) continue;
        const base = pc.position === 'fixed' || cs.position === 'static' ? { left: 0, top: 0, right: innerWidth, bottom: innerHeight } : rect;
        const pw = parseFloat(pc.width), ph = parseFloat(pc.height);
        const spans = Number.isFinite(pw) && Number.isFinite(ph) ? { left: base.left, top: base.top, right: base.left + pw, bottom: base.top + ph } : base;
        const a = darkAlpha(pc);
        if (a && covers(spans)) hits.push({ el: label(el) + ps, alpha: a });
      }
    }
    return hits;
  };
  // svg <text> bbox mapped into its owning svg's user space, compared with that svg's viewBox
  const svgTextOut = el => {
    const svg = el.ownerSVGElement; if (!svg || !svg.getScreenCTM || getComputedStyle(svg).overflow === 'visible') return false;
    const vb = svg.viewBox.baseVal, hasVb = vb && vb.width > 0;
    const x0 = hasVb ? vb.x : 0, y0 = hasVb ? vb.y : 0, w = hasVb ? vb.width : svg.clientWidth, h = hasVb ? vb.height : svg.clientHeight;
    const b = el.getBBox(), tm = svg.getScreenCTM().inverse().multiply(el.getScreenCTM());
    const pts = [[b.x, b.y], [b.x + b.width, b.y], [b.x, b.y + b.height], [b.x + b.width, b.y + b.height]].map(([x, y]) => [tm.a * x + tm.c * y + tm.e, tm.b * x + tm.d * y + tm.f]);
    const xs = pts.map(p => p[0]), ys = pts.map(p => p[1]), EPS = 1;
    return Math.min(...xs) < x0 - EPS || Math.max(...xs) > x0 + w + EPS || Math.min(...ys) < y0 - EPS || Math.max(...ys) > y0 + h + EPS;
  };
  const clipped = () => {
    const hits = [];
    for (const el of document.querySelectorAll('body *')) {
      if (el.closest('defs,template,noscript') || /^(script|style|noscript)$/i.test(el.tagName)) continue;
      const st = state(el); if (st.gone || !st.vis || st.op === 0) continue;
      const r = el.getBoundingClientRect(); if (!r.width || !r.height) continue;
      if (r.width <= 2 || r.height <= 2) continue; // a visually-hidden (sr-only) element is clipped on purpose
      if (el.closest('svg')) {
        if (/^text$/i.test(el.tagName) && norm(el.textContent) && svgTextOut(el)) hits.push({ text: norm(el.textContent).slice(0, 40), why: 'svg text crosses its viewport edge' });
        continue;
      }
      const cs = getComputedStyle(el);
      if (ownText(el) && /hidden|clip/.test(cs.overflowX) && cs.textOverflow !== 'ellipsis' && el.clientWidth > 0 && el.scrollWidth > el.clientWidth + 1) {
        hits.push({ text: ownText(el).slice(0, 40), why: `scrollWidth ${el.scrollWidth} > clientWidth ${el.clientWidth} with overflow hidden` });
      }
    }
    return hits;
  };
  window.__foldCraft = { hidden, overlay, clipped };
})();
