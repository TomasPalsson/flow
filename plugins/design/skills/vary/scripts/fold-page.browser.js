// fold-page.browser.js — page-level measures fold-check.mjs injects (page.addScriptTag), then calls as
// window.__foldPage.overflow() / .meta(). Browser-side only: no imports.
//   overflow  (B1) horizontal overflow: documentElement.scrollWidth > innerWidth + 1, or a visible text/img/svg/video/canvas/iframe/table
//             element crossing the viewport edge (right > innerWidth + 1 or left < -1) with no ancestor that scrolls or clips on x
//   meta      (B2) designer/scaffold language in the visible text (script/style/code/pre and [data-meta-ok] subtrees excluded)
(() => {
  const norm = s => (s || '').replace(/\s+/g, ' ').trim();
  const label = el => `${el.tagName.toLowerCase()}${typeof el.className === 'string' && el.className.trim() ? '.' + el.className.trim().split(/\s+/)[0] : ''}`;
  const shown = el => el.checkVisibility({ opacityProperty: true, visibilityProperty: true });
  const srOnly = el => {
    const s = getComputedStyle(el), r = el.getBoundingClientRect();
    return /^rect\(\s*0/.test(s.clip) || /inset\(\s*50%/.test(s.clipPath) || (r.width <= 1 && r.height <= 1);
  };
  const contained = el => {
    for (let n = el.parentElement; n; n = n.parentElement) if (/^(auto|scroll|hidden|clip)$/.test(getComputedStyle(n).overflowX)) return true;
    return false;
  };
  const overflow = () => {
    const vw = innerWidth, out = [];
    for (const el of document.querySelectorAll('body *')) {
      const tag = el.tagName.toLowerCase();
      if (el.closest('svg') && tag !== 'svg') continue;
      const own = norm([...el.childNodes].filter(n => n.nodeType === 3).map(n => n.nodeValue).join(' '));
      if (!own && !/^(img|svg|video|canvas|iframe|table)$/.test(tag)) continue;
      const r = el.getBoundingClientRect();
      // wholly off either edge is a hide pattern (left:-9999px, a closed drawer translated out), not a layout bug
      if (r.width === 0 || r.height === 0 || r.right <= 0 || r.left >= vw || !shown(el) || srOnly(el)) continue;
      if ((r.right > vw + 1 || r.left < -1) && !contained(el)) out.push({ el: label(el), text: own.slice(0, 30), right: Math.round(r.right) });
    }
    // html or body clipping x means the page cannot scroll sideways, whatever scrollWidth says
    const clipsX = [document.documentElement, document.body].some(e => /^(hidden|clip)$/.test(getComputedStyle(e).overflowX));
    return { scrollWidth: clipsX ? vw : document.documentElement.scrollWidth, vw, offenders: out.slice(0, 5), total: out.length };
  };
  const PATTERNS = ['signature device', 'design notes?', 'art direction', 'hero treatment', 'text equivalent of', 'the drawing above', 'drawn, not generated',
    'placeholder', 'lorem ipsum', 'wireframe', 'will plot here', 'once telemetry', 'is wired', 'mock-?up', 'this section shows'];
  const REGEXES = [...PATTERNS.map(p => new RegExp(`\\b${p}\\b`, 'gi')), /\b(TODO|TBD)\b/g, /\bconcept:/gi, /\bREF [A-Z]{2,}-[A-Z0-9-]+/g];
  const meta = () => {
    const parts = [], walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    for (let n = walker.nextNode(); n; n = walker.nextNode()) {
      const el = n.parentElement;
      if (!el || !n.nodeValue.trim() || el.closest('script,style,noscript,template,code,pre,[data-meta-ok]') || !shown(el)) continue;
      parts.push(n.nodeValue);
    }
    const text = norm(parts.join(' ')), hits = [];
    for (const re of REGEXES) {
      for (const m of text.matchAll(re)) {
        const pad = Math.max(0, Math.floor((40 - m[0].length) / 2)), s = Math.max(0, m.index - pad);
        hits.push({ term: m[0], context: text.slice(s, m.index + m[0].length + pad) });
      }
    }
    return hits;
  };
  window.__foldPage = { overflow, meta };
})();
