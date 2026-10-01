// fold-content.browser.js — the content measures fold-check.mjs injects into the page (page.addScriptTag), then calls as
// window.__foldContent.headline() and window.__foldContent.duplicates(). Browser-side only: no imports.
//   headline    a visible level-1 heading in the first viewport plus another visible text line within 200px of it
//   duplicates  (full page, footer excluded) text blocks >= 40 chars that appear twice, and price lists (>= 3 amounts in one
//               block, HTML or svg text) that share >= 3 amounts with another non-nested block
(() => {
  const visible = el => {
    for (let n = el; n && n.nodeType === 1; n = n.parentElement) {
      const s = getComputedStyle(n);
      if (s.display === 'none' || s.visibility === 'hidden' || +s.opacity === 0) return false;
    }
    return true;
  };
  const norm = s => (s || '').replace(/\s+/g, ' ').trim();
  const inFooter = el => !!el.closest('footer,[role="contentinfo"],#footer,.footer,.site-footer');
  const ownText = el => norm([...el.childNodes].filter(n => n.nodeType === 3).map(n => n.nodeValue).join(' '));
  const INERT = 'script,style,noscript,template,defs,title,desc';

  const headline = () => {
    scrollTo({ top: 0, left: 0, behavior: 'instant' }); // earlier plate screenshots scroll the page; css smooth-scroll must not delay it
    const vw = innerWidth, vh = innerHeight;
    const inView = r => r.width >= 20 && r.height >= 10 && r.bottom > 0 && r.top < vh && r.right > 0 && r.left < vw;
    const h1 = [...document.querySelectorAll('h1,[role="heading"][aria-level="1"]')].find(e => visible(e) && norm(e.textContent) && inView(e.getBoundingClientRect()));
    if (!h1) return { h1: null, line: null };
    const hr = h1.getBoundingClientRect();
    let line = null;
    for (const el of document.querySelectorAll('body *')) {
      if (el === h1 || h1.contains(el) || el.closest(`nav,button,${INERT}`)) continue;
      const t = ownText(el);
      if (t.length < 10 || !/\s/.test(t) || !visible(el)) continue;
      const r = el.getBoundingClientRect();
      if (!inView(r)) continue;
      const gap = Math.max(0, r.top - hr.bottom, hr.top - r.bottom);
      if (gap <= 200) { line = t.slice(0, 60); break; }
    }
    return { h1: norm(h1.textContent).slice(0, 40), line };
  };

  const AMOUNT = /(?:[£$€]\s?\d[\d.,]*|\d[\d.,]*\s?(?:kr\.?|isk|dkk|nok|sek|eur|usd|gbp|[£$€]))/gi;
  const count = s => (s.match(AMOUNT) || []).length;
  const amountsOf = s => [...new Set((s.match(AMOUNT) || []).map(a => a.replace(/\D/g, '')))];
  // A repeated card template (a sibling of the same tag and first class within 4 levels) legitimately repeats its text and
  // price tiers; two occurrences with the same template signature are not duplicated content.
  const cls = n => n.tagName.toLowerCase() + '.' + (n.classList[0] || '');
  const templated = el => {
    for (let n = el, i = 0; n && n !== document.body && i < 4; n = n.parentElement, i++) {
      if (n.classList.length && [...n.parentElement.children].some(c => c !== n && cls(c) === cls(n))) return true;
    }
    return false;
  };
  const sig = el => { const out = []; for (let n = el, i = 0; n && i < 2; n = n.parentElement, i++) out.push(cls(n)); return out.join('>'); };
  const sameTemplate = (a, b) => templated(a) && templated(b) && sig(a) === sig(b);
  const name = b => b.tagName.toLowerCase() + (b.id ? '#' + b.id : '') + (b.classList[0] ? '.' + b.classList[0] : '');

  const repeatedText = () => {
    const seen = new Map();
    for (const el of document.querySelectorAll('body *')) {
      if (el.closest(`${INERT},svg`) || inFooter(el) || !visible(el)) continue;
      const t = norm(el.textContent);
      if (t.length < 40 || [...el.children].some(c => norm(c.textContent).length >= 40)) continue;
      const k = t.toLowerCase(); seen.set(k, [...(seen.get(k) || []), el]);
    }
    return [...seen].filter(([, els]) => els.some((a, i) => els.slice(i + 1).some(b => !sameTemplate(a, b)))).map(([k, els]) => ({ text: k.slice(0, 60), n: els.length }));
  };

  const repeatedPrices = () => {
    const blocks = new Set();
    for (const el of document.querySelectorAll('body *')) {
      if (el.closest(INERT) || inFooter(el) || !visible(el)) continue;
      const isText = el.tagName.toLowerCase() === 'text';
      if (!count(isText ? norm(el.textContent) : el.closest('svg') ? '' : ownText(el))) continue;
      let b = el;
      while (b && b !== document.body && count(b.textContent || '') < 3) b = b.parentElement;
      if (b && b !== document.body) blocks.add(b);
    }
    const list = [...blocks].map(b => ({ b, amounts: amountsOf(b.textContent || '') }));
    const out = [];
    for (let i = 0; i < list.length; i++) {
      for (let j = i + 1; j < list.length; j++) {
        const A = list[i], B = list[j];
        if (A.b.contains(B.b) || B.b.contains(A.b) || sameTemplate(A.b, B.b)) continue;
        const shared = A.amounts.filter(a => B.amounts.includes(a));
        if (shared.length >= 3) out.push({ amounts: shared.slice(0, 6), a: name(A.b), b: name(B.b) });
      }
    }
    return out;
  };

  window.__foldContent = { headline, duplicates: () => ({ text: repeatedText(), prices: repeatedPrices() }) };
})();
