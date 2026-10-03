// fold-text.browser.js — the text-collision measure fold-check.mjs injects into the page
// (page.addScriptTag), then calls as window.__foldText(). Browser-side only: no imports.
// Three passes over every visible text box in the first viewport: text over text, text under
// an opaque later-painted element, and svg shapes crossing (or half-swallowing) a text box.
(() => {
  const vw = () => innerWidth, vh = () => innerHeight;
  const label = el => (el.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 40);
  const effOpacity = el => { let o = 1; for (let n = el; n && n.nodeType === 1; n = n.parentElement) o *= +getComputedStyle(n).opacity; return o; };
  const visible = el => {
    for (let n = el; n && n.nodeType === 1; n = n.parentElement) {
      const s = getComputedStyle(n);
      if (s.display === 'none' || s.visibility === 'hidden' || +s.opacity === 0) return false;
    }
    return true;
  };
  const alphaOf = c => {
    if (!c || c === 'transparent') return 0;
    const m = c.match(/(?:,|\/)\s*([\d.]+)(%?)\s*\)$/);
    return m ? (m[2] ? +m[1] / 100 : +m[1]) : 1;
  };
  const SHAPE = /^(path|rect|circle|ellipse|polygon|polyline)$/i;
  const GEO = /^(path|rect|circle|ellipse|polygon|polyline|line)$/i;
  const NOT_PAINTED = 'defs,symbol,clipPath,mask,pattern,marker,template';
  const area = r => (r.x2 - r.x1) * (r.y2 - r.y1);
  const shrink = r => { const dy = (r.y2 - r.y1) * 0.15; return { x1: r.x1, x2: r.x2, y1: r.y1 + dy, y2: r.y2 - dy }; };
  const inter = (a, b) => Math.max(0, Math.min(a.x2, b.x2) - Math.max(a.x1, b.x1)) * Math.max(0, Math.min(a.y2, b.y2) - Math.max(a.y1, b.y1));
  const boxesMeet = (s, b) => Math.min(s.x2, b.x2) > Math.max(s.x1, b.x1) && Math.min(s.y2, b.y2) > Math.max(s.y1, b.y1);
  const num = v => (v === 'auto' || v === '' ? 0 : +v || 0);
  const effZ = el => { let z = 0; for (let n = el; n && n.nodeType === 1; n = n.parentElement) { const s = getComputedStyle(n); if (s.position !== 'static') z = Math.max(z, num(s.zIndex)); } return z; };
  const rgbOf = c => { const m = (c || '').match(/^rgba?\(\s*(\d+)[ ,]+(\d+)[ ,]+(\d+)/); return m ? [+m[1], +m[2], +m[3]] : null; };
  const lum = c => { const f = v => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; }; return 0.2126 * f(c[0]) + 0.7152 * f(c[1]) + 0.0722 * f(c[2]); };
  const contrast = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };

  function opaque(e, t) {
    if (e === document.documentElement || e === document.body || e.contains(t) || t.contains(e)) return false;
    if (effOpacity(e) < 0.95) return false;
    const cs = getComputedStyle(e), tag = e.tagName;
    if (/^(img|video|canvas)$/i.test(tag)) return true;
    if (SHAPE.test(tag)) return cs.fill !== 'none' && +cs.fillOpacity >= 0.95;
    if (e instanceof SVGElement) return false;
    return alphaOf(cs.backgroundColor) >= 0.95 || /url\(/.test(cs.backgroundImage);
  }

  function textItems() {
    const items = [];
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    for (let n = walker.nextNode(); n; n = walker.nextNode()) {
      if (!n.nodeValue.trim()) continue;
      const el = n.parentElement;
      if (!el || el.closest('script,style,noscript,title,desc,' + NOT_PAINTED + ',head') || !visible(el)) continue;
      const range = document.createRange(); range.selectNodeContents(n);
      const rects = [...range.getClientRects()]
        .map(r => ({ x1: Math.max(0, r.left), y1: Math.max(0, r.top), x2: Math.min(vw(), r.right), y2: Math.min(vh(), r.bottom) }))
        .filter(r => r.x2 - r.x1 >= 4 && r.y2 - r.y1 >= 4);
      if (rects.length) items.push({ el, text: n.nodeValue.replace(/\s+/g, ' ').trim().slice(0, 40), rects });
    }
    return items;
  }

  // the same words stacked at almost the same spot = layered lettering (emboss, drop shadow, outline):
  // ara-bar's sign sets "ARA" and the phone that way; a real duplicate label sits further off
  function layeredCopy(A, B) {
    if (A.text !== B.text) return false;
    if (A.el.closest('[aria-hidden="true"]') || B.el.closest('[aria-hidden="true"]')) return true;
    const near = (a, b) => Math.abs(a.x1 - b.x1) + Math.abs(a.y1 - b.y1) <= 0.15 * Math.max(a.y2 - a.y1, b.y2 - b.y1) + 2;
    return A.rects.length === B.rects.length && A.rects.every((a, k) => near(a, B.rects[k]));
  }

  function textOverText(items) {
    const hits = [];
    for (let i = 0; i < items.length; i++) {
      for (let j = i + 1; j < items.length; j++) {
        const A = items[i], B = items[j];
        if (A.el === B.el || layeredCopy(A, B)) continue;
        const bad = A.rects.some(a => B.rects.some(b => { const sa = shrink(a), sb = shrink(b); return inter(sa, sb) > 0.2 * Math.min(area(sa), area(sb)); }));
        if (bad) hits.push({ a: A.text, b: B.text, why: 'text boxes overlap' });
      }
    }
    return hits;
  }

  function textUnderOpaque(items) {
    const hits = [];
    for (const it of items) {
      let found = 0, covered = 0, by = null;
      for (const r of it.rects) {
        for (let gy = 0; gy < 3; gy++) for (let gx = 0; gx < 6; gx++) {
          const stack = document.elementsFromPoint(r.x1 + (r.x2 - r.x1) * (gx + 0.5) / 6, r.y1 + (r.y2 - r.y1) * (gy + 0.5) / 3);
          const at = stack.findIndex(e => e === it.el || it.el.contains(e));
          if (at < 0) continue;
          found++;
          const cover = stack.slice(0, at).find(e => opaque(e, it.el));
          if (cover) { covered++; by = by || cover; }
        }
      }
      if (found && covered / found > 0.3) hits.push({ a: it.text, b: label(by) || `<${by.tagName.toLowerCase()}>`, why: `${Math.round(100 * covered / found)}% covered by an opaque later-painted <${by.tagName.toLowerCase()}>` });
    }
    return hits;
  }

  // Any painted svg shape (fill or stroke, even a hairline, even pointer-events:none) in the fold.
  function paintedShapes() {
    const shapes = [];
    for (const el of document.querySelectorAll('svg *')) {
      if (!GEO.test(el.tagName) || el.closest(NOT_PAINTED) || !visible(el) || effOpacity(el) < 0.95) continue;
      const cs = getComputedStyle(el), sw = parseFloat(cs.strokeWidth) || 0;
      const fill = cs.fill !== 'none' && +cs.fillOpacity >= 0.95 && !/^line$/i.test(el.tagName);
      const stroke = cs.stroke !== 'none' && sw > 0 && +cs.strokeOpacity >= 0.95;
      if (!fill && !stroke) continue;
      const r = el.getBoundingClientRect(), m = el.getScreenCTM();
      const pad = stroke ? sw * Math.max(1, m ? Math.hypot(m.a, m.b) : 1) / 2 + 1 : 1;
      if (r.right + pad < 0 || r.left - pad > vw() || r.bottom + pad < 0 || r.top - pad > vh()) continue;
      shapes.push({ el, fill, stroke, rgb: fill ? rgbOf(cs.fill) : null, box: { x1: r.left - pad, y1: r.top - pad, x2: r.right + pad, y2: r.bottom + pad }, z: effZ(el.ownerSVGElement || el) });
    }
    return shapes;
  }

  function shapeLabel(el) {
    const bits = [];
    for (let n = el; n && n.nodeType === 1 && bits.length < 2; n = n.parentElement) {
      const nm = n.id || n.getAttribute('aria-label') || (typeof n.className === 'string' ? n.className : n.className && n.className.baseVal) || '';
      if (nm) bits.push(`${n === el ? '' : 'in '}${n.tagName.toLowerCase()}${n.id ? '#' + n.id : ' ' + String(nm).trim().split(/\s+/)[0]}`);
      if (n.tagName.toLowerCase() === 'svg') break;
    }
    let cm = '';
    for (let n = el; n && n.nodeType === 1 && !cm; n = n.parentElement) for (let q = n.previousSibling; q && !cm; q = q.previousSibling) if (q.nodeType === 8) cm = q.nodeValue.trim().slice(0, 40);
    return `<${el.tagName.toLowerCase()}>${bits.length ? ' ' + bits.join(' ') : ''}${cm ? ` (after "${cm}")` : ''}`;
  }

  // painted under the text: only a low-contrast fill the text straddles the edge of (a callout set half over a dark plate)
  function straddlesLowContrast(it, sh, inv) {
    if (!sh.fill || !sh.rgb) return false;
    const tc = rgbOf(getComputedStyle(it.el)[it.el instanceof SVGElement ? 'fill' : 'color']);
    if (!tc || contrast(tc, sh.rgb) >= 3) return false;
    for (const r of it.rects) {
      const s = shrink(r); let tot = 0, inn = 0;
      if (!boxesMeet(s, sh.box)) continue;
      for (let y = s.y1 + 1; y < s.y2; y += 2) for (let x = s.x1 + 1; x < s.x2; x += 2) {
        tot++;
        if (sh.el.isPointInFill(new DOMPoint(x, y).matrixTransform(inv))) inn++;
      }
      if (tot && inn / tot >= 0.08 && inn / tot <= 0.92) return true;
    }
    return false;
  }

  // painted over the text: two sample points inside the text box land in the shape's fill or stroke
  function crossesText(it, sh, inv) {
    for (const r of it.rects) {
      const s = shrink(r);
      if (!boxesMeet(s, sh.box)) continue;
      let n = 0;
      for (let y = s.y1 + 1; y < s.y2; y += 2) for (let x = s.x1 + 1; x < s.x2; x += 2) {
        if (x < sh.box.x1 || x > sh.box.x2 || y < sh.box.y1 || y > sh.box.y2) continue;
        const pt = new DOMPoint(x, y).matrixTransform(inv);
        if (((sh.fill && sh.el.isPointInFill(pt)) || (sh.stroke && sh.el.isPointInStroke(pt))) && ++n >= 2) return true;
      }
    }
    return false;
  }

  function shapeOverText(items) {
    const shapes = paintedShapes(), hits = [], hitTexts = new Set();
    for (const it of items) {
      // a one- or two-character label (a sheet-grid coordinate, a callout number) may sit on the drawing's own lines
      if (it.text.length <= 2) continue;
      const tz = effZ(it.el);
      for (const sh of shapes) {
        if (sh.el === it.el || sh.el.contains(it.el) || it.el.contains(sh.el)) continue;
        const m = sh.el.getScreenCTM(); if (!m) continue;
        const inv = m.inverse();
        const following = !!(it.el.compareDocumentPosition(sh.el) & Node.DOCUMENT_POSITION_FOLLOWING);
        const later = sh.z > tz || (sh.z === tz && following);
        const under = !later && straddlesLowContrast(it, sh, inv);
        if (!under && !(later && crossesText(it, sh, inv))) continue;
        // a shape crossing the text explains an 'opaque cover' report; a straddled edge does not
        if (!under) hitTexts.add(it.text);
        hits.push({ a: it.text, b: shapeLabel(sh.el), why: under ? `straddles the edge of a low-contrast svg <${sh.el.tagName.toLowerCase()}> fill, so part of it is lost against the art` : `crossed by a later-painted svg ${sh.stroke && !sh.fill ? 'stroke' : 'shape'} <${sh.el.tagName.toLowerCase()}>` });
        break;
      }
    }
    return { hits, hitTexts };
  }

  window.__foldText = () => {
    const items = textItems();
    const geo = shapeOverText(items);
    const covered = textUnderOpaque(items).filter(h => !geo.hitTexts.has(h.a));
    return { texts: items.length, hits: [...textOverText(items), ...covered, ...geo.hits] };
  };
})();
