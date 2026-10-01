import menu from './menu.json';

// FNV-1a + mulberry32: seeded per item so every load draws the same pizza.
function rng(key) {
  let h = 2166136261;
  for (const c of key) { h ^= c.charCodeAt(0); h = Math.imul(h, 16777619); }
  return () => { h |= 0; h = (h + 0x6d2b79f5) | 0; let t = Math.imul(h ^ (h >>> 15), 1 | h); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}
export function pizza(item) {
  const r = rng('pizza:' + item.id);
  const dots = item.toppings.map(() => `<circle cx="${20 + Math.random() * 60}" cy="${20 + Math.random() * 60}" r="6"/>`).join('');
  return `<svg viewBox="0 0 100 100" aria-hidden="true"><circle cx="50" cy="50" r="46"/>${dots}</svg>`;
}
document.getElementById('art').innerHTML = menu.map(pizza).join('');
