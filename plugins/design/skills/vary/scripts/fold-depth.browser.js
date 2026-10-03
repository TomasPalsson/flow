// fold-depth.browser.js — the frame / solid-card / plate / rendering-depth measures fold-check.mjs injects into the
// page (page.addScriptTag) and calls through window.__foldDepth. Browser-side only: no imports.
//   frame()      hero art union box (boxes >= 8% of the viewport) and its margins to the viewport edges      (G1)
//   cards()      text containers with an opaque background covering > 6% of the hero art area               (G3)
//   plates()     per below-fold section (tagged data-fold-sec): its largest drawn plate, tagged data-fold-plate (G4)
//   stats(b64, rect)  value range, value steps and flat-block texture of a screenshot region                 (G2)
(() => {
  const ART = /^(svg|canvas|img|video)$/i;
  const alphaOf = c => {
    if (!c || c === 'transparent') return 0;
    const m = c.match(/(?:,|\/)\s*([\d.]+)(%?)\s*\)$/);
    return m ? (m[2] ? +m[1] / 100 : +m[1]) : 1;
  };
  const shown = el => {
    for (let n = el; n && n.nodeType === 1; n = n.parentElement) {
      const s = getComputedStyle(n);
      if (s.display === 'none' || s.visibility === 'hidden' || +s.opacity === 0) return false;
    }
    return true;
  };
  const isArt = el => {
    const cs = getComputedStyle(el);
    return ART.test(el.tagName) || /url\(/.test(cs.backgroundImage) || /url\(/.test(cs.maskImage || cs.webkitMaskImage || '');
  };
  const nested = el => !!(el.parentElement && el.parentElement.closest('svg'));
  const artEls = root => [...root.querySelectorAll('svg,canvas,img,video,*')].filter(e => isArt(e) && !nested(e) && shown(e));
  const clipped = (r, vw, vh) => {
    const c = { x1: Math.max(0, r.left), y1: Math.max(0, r.top), x2: Math.min(vw, r.right), y2: Math.min(vh, r.bottom) };
    return c.x2 > c.x1 && c.y2 > c.y1 ? c : null;
  };
  const union = rects => {
    const xs = [...new Set(rects.flatMap(r => [r.x1, r.x2]))].sort((a, b) => a - b);
    let area = 0;
    for (let i = 0; i < xs.length - 1; i++) {
      const iv = rects.filter(r => r.x1 <= xs[i] && r.x2 >= xs[i + 1]).map(r => [r.y1, r.y2]).sort((a, b) => a[0] - b[0]);
      let end = -Infinity;
      for (const [a, b] of iv) { if (b > end) { area += (b - Math.max(a, end)) * (xs[i + 1] - xs[i]); end = b; } }
    }
    return area;
  };
  const heroArt = () => {
    const vw = innerWidth, vh = innerHeight, boxes = [];
    for (const el of artEls(document)) {
      const c = clipped(el.getBoundingClientRect(), vw, vh);
      if (c && (c.x2 - c.x1) * (c.y2 - c.y1) >= 0.08 * vw * vh) boxes.push(c);
    }
    return boxes;
  };
  const bounds = boxes => ({
    x1: Math.min(...boxes.map(b => b.x1)), y1: Math.min(...boxes.map(b => b.y1)),
    x2: Math.max(...boxes.map(b => b.x2)), y2: Math.max(...boxes.map(b => b.y2)),
  });

  const frame = () => {
    const boxes = heroArt(), vw = innerWidth;
    if (!boxes.length) return { none: true, span: 0, left: 0, right: vw };
    const b = bounds(boxes);
    return { none: false, span: (b.x2 - b.x1) / vw, left: Math.round(b.x1), right: Math.round(vw - b.x2), box: b };
  };

  const cards = () => {
    const vw = innerWidth, vh = innerHeight, boxes = heroArt(), arts = artEls(document);
    const total = union(boxes), hits = [];
    if (!total) return hits;
    for (const el of document.querySelectorAll('body *')) {
      if (el.closest('svg,defs,template') || /^(script|style|noscript)$/i.test(el.tagName)) continue;
      if (alphaOf(getComputedStyle(el).backgroundColor) < 0.95 || !shown(el)) continue;
      const text = (el.textContent || '').replace(/\s+/g, ' ').trim();
      if (!text || arts.some(e => e === el || el.contains(e) || e.contains(el))) continue;
      const c = clipped(el.getBoundingClientRect(), vw, vh);
      if (!c || (c.x2 - c.x1 >= 0.95 * vw && c.y2 - c.y1 <= 120)) continue; // a full-width nav bar is not a card
      const part = boxes.map(b => ({ x1: Math.max(b.x1, c.x1), y1: Math.max(b.y1, c.y1), x2: Math.min(b.x2, c.x2), y2: Math.min(b.y2, c.y2) })).filter(r => r.x2 > r.x1 && r.y2 > r.y1);
      const share = union(part) / total;
      if (share > 0.06) hits.push({ text: text.slice(0, 40), share });
    }
    return hits;
  };

  // largest drawn element (>= 150x80px) per tagged section
  const plates = () => {
    document.querySelectorAll('[data-fold-plate]').forEach(e => e.removeAttribute('data-fold-plate'));
    const out = [];
    document.querySelectorAll('[data-fold-sec]').forEach(sec => {
      let best = null;
      for (const el of artEls(sec)) {
        const b = el.getBoundingClientRect();
        if (b.width < 150 || b.height < 80 || (best && b.width * b.height <= best.w * best.h)) continue;
        best = { el, w: b.width, h: b.height };
      }
      if (!best) return;
      const id = sec.getAttribute('data-fold-sec');
      best.el.setAttribute('data-fold-plate', id);
      out.push({ id, name: sec.getAttribute('data-fold-name'), w: Math.round(best.w), h: Math.round(best.h), secW: Math.round(sec.getBoundingClientRect().width) });
    });
    return out;
  };

  const stats = async (b64, rect) => {
    const img = new Image(); img.src = 'data:image/png;base64,' + b64; await img.decode();
    const R = rect || { x1: 0, y1: 0, x2: img.width, y2: img.height };
    const x = Math.floor(R.x1), y = Math.floor(R.y1), w = Math.min(img.width - x, Math.floor(R.x2 - R.x1)), h = Math.min(img.height - y, Math.floor(R.y2 - R.y1));
    if (w < 8 || h < 8) return { range: 0, steps: 0, texture: 0 };
    const cv = document.createElement('canvas'); cv.width = w; cv.height = h;
    const ctx = cv.getContext('2d'); ctx.drawImage(img, x, y, w, h, 0, 0, w, h);
    const d = ctx.getImageData(0, 0, w, h).data, lum = new Float32Array(w * h), hist = new Array(256).fill(0);
    for (let i = 0; i < w * h; i++) { const l = 0.2126 * d[i * 4] + 0.7152 * d[i * 4 + 1] + 0.0722 * d[i * 4 + 2]; lum[i] = l; hist[Math.round(l)]++; }
    const pct = q => { let a = 0; for (let v = 0; v < 256; v++) { a += hist[v]; if (a >= q * w * h) return v; } return 255; };
    const bins = new Array(16).fill(0);
    for (let v = 0; v < 256; v++) bins[v >> 4] += hist[v];
    const sds = [];
    for (let by = 0; by + 8 <= h; by += 8) for (let bx = 0; bx + 8 <= w; bx += 8) {
      let s = 0, q = 0;
      for (let j = 0; j < 8; j++) for (let k = 0; k < 8; k++) { const l = lum[(by + j) * w + bx + k]; s += l; q += l * l; }
      sds.push(Math.sqrt(Math.max(0, q / 64 - (s / 64) ** 2)));
    }
    sds.sort((a, b) => a - b);
    const flat = sds.slice(0, Math.max(1, Math.floor(sds.length * 0.3)));
    return { range: pct(0.95) - pct(0.05), steps: bins.filter(n => n >= 0.02 * w * h).length, texture: flat.reduce((a, b) => a + b, 0) / flat.length };
  };
  window.__foldDepth = { frame, cards, plates, stats };
})();
