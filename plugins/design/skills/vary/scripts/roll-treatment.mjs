// roll-treatment.mjs — hero treatment model for roll.mjs (vary SKILL Step 3a): which treatment a concept carries, what each
// treatment obliges, and how dossier directives lock the roll. Pure functions; roll.mjs owns I/O and exits.

// signature-device techniques (graphics.md section 2)
export const TECHNIQUES = ['seeded-illustration', 'procedural-subject', 'traced-line', 'mechanism-diagram',
  'annotated-photo', 'photo-direction', 'product-capture', 'scroll-scene', 'data-diagram', 'material-texture', 'print-process',
  'typographic', 'generative-pattern', 'shader'];
export const TREATMENTS = ['scene', 'pattern', 'photography', 'product-ui', 'typography', 'data-visual', 'utility'];
export const TECH_TREATMENT = {
  'seeded-illustration': 'scene', 'procedural-subject': 'scene', 'scroll-scene': 'scene', 'traced-line': 'scene',
  'mechanism-diagram': 'scene', 'print-process': 'scene',
  'generative-pattern': 'pattern', 'material-texture': 'pattern', shader: 'pattern',
  'annotated-photo': 'photography', 'photo-direction': 'photography',
  'product-capture': 'product-ui', typographic: 'typography', 'data-diagram': 'data-visual',
};
export const MODE_TREATMENTS = {
  operate: ['utility', 'data-visual', 'product-ui', 'typography'],
  read: ['utility', 'typography', 'data-visual', 'photography', 'pattern'],
  persuade: TREATMENTS.filter(t => t !== 'utility'),
  experience: TREATMENTS.filter(t => t !== 'utility'),
};
export const isLead = mode => mode === 'persuade' || mode === 'experience';
export const fallbackTreatment = mode => (isLead(mode) ? 'typography' : 'utility');
export const allowedFor = (mode, t) => (MODE_TREATMENTS[mode] || []).includes(t);
export const drawn = t => t === 'scene' || t === 'pattern';

export const OBLIGATION = {
  scene: 'a full-bleed drawn scene or sheet; the scene bar (SKILL Step 3a S1-S8) applies',
  pattern: 'a generative, material or print field carrying the type; brief and gallery critique, no crew',
  photography: 'client photos from dossier.assets shown faithfully as the hero; crop, sequence and grade are the signature; the scene bar does not apply',
  'product-ui': 'the real product capture or live UI shown faithfully, tied to a named workflow; DPR-2 captures, callouts allowed; the scene bar does not apply',
  typography: 'type is the picture: a typographic system or lettering idea that encodes a fact; no drawn scene is required',
  'data-visual': "a bespoke chart or diagram built from the dossier's data, with a text equivalent",
  utility: 'no hero: the tool or document is the first screen; the details carry the signature; a visible page title in the fold',
};
const SCALE = {
  scene: 'hero, divider, micro (icon/bullet/empty state)', pattern: 'hero, divider, micro (icon/bullet/empty state)',
  utility: 'details: icons, numerals, empty states',
};
export const scaleLine = t => (SCALE[t] ? `must appear at 3 scales: ${SCALE[t]}` : 'must appear at hero and one more scale');
export const minDevices = t => (!t || drawn(t) ? 2 : t === 'utility' ? 0 : 1);

// a reason string when the concept's treatment, device count or grounding is invalid; null when fine
export function treatmentProblem(c, dossier) {
  const t = c.treatment;
  if (t !== undefined && !TREATMENTS.includes(t)) return `treatment must be one of ${TREATMENTS.join(', ')}, got ${t}`;
  const n = Array.isArray(c.devices) ? c.devices.length : 0;
  if (n < minDevices(t)) return `needs at least ${minDevices(t)} device${minDevices(t) === 1 ? '' : 's'}${t ? ` for treatment ${t}` : ''}, got ${n}`;
  if (t && t !== 'typography' && t !== 'utility' && !c.devices.some(d => TECH_TREATMENT[d.technique] === t)) {
    const need = Object.entries(TECH_TREATMENT).filter(([, v]) => v === t).map(([k]) => k);
    return `treatment ${t} needs at least one device whose technique maps to it (${need.join(', ')})`;
  }
  const assets = Array.isArray(dossier?.assets) ? dossier.assets : [];
  if (t === 'photography' && !assets.some(a => a && a.kind === 'photo' && a.usable === true)) return 'treatment photography needs at least one dossier.assets[] entry with kind "photo" and usable: true';
  const screens = dossier?.product?.screens;
  const described = Array.isArray(screens) && screens.length > 0 && screens.every(x => typeof x === 'string' && x.trim());
  if (t === 'product-ui' && !assets.some(a => a && a.kind === 'screenshot') && !(typeof dossier?.product?.app_path === 'string' && dossier.product.app_path.trim()) && !described) return 'treatment product-ui needs a dossier.assets[] entry with kind "screenshot", a non-empty dossier.product.app_path, or a non-empty dossier.product.screens[] (screens described in the brief, rebuilt in HTML from the facts)';
  return null;
}

// Merge dossier.directives[].locks ("key=value") into locks. Directives outrank the CLI: a conflicting CLI lock is an error string.
export function mergeDirectiveLocks(locks, dossier) {
  const cli = { ...locks };
  for (const d of dossier?.directives || []) {
    for (const s of d?.locks || []) {
      const [k, ...rest] = String(s).split('='), v = rest.join('=');
      if (k in cli && cli[k] !== v) return `directive "${d.text}" locks ${k}=${v}; the CLI asked ${cli[k]}`;
      locks[k] = v;
    }
  }
  return null;
}

// Choose the treatment for a dealt concept and its tentative device. fromDevice = derived from the device (keep that device).
export function resolveTreatment({ concept, device, mode, lock }) {
  const notes = [];
  let t, fromDevice = false;
  if (lock) {
    t = lock;
    if (concept?.treatment && concept.treatment !== lock) notes.push(`treatment locked to ${lock}; concept ${concept.id} names ${concept.treatment}, overridden`);
    else notes.push(`treatment locked to ${lock}`);
  } else if (concept?.treatment) t = concept.treatment;
  else if (device) { t = TECH_TREATMENT[device.technique]; fromDevice = true; }
  else t = fallbackTreatment(mode);
  if (!lock && !allowedFor(mode, t)) {
    const fb = fallbackTreatment(mode);
    notes.push(`treatment ${t} is not allowed for mode ${mode}; fell back to ${fb}`);
    t = fb; fromDevice = false;
  }
  return { treatment: t, fromDevice, notes, locked: !!lock };
}

export function directiveLines(dossier) {
  return (dossier?.directives || []).map(d => `DIRECTIVES: "${d.text}"${d.locks?.length ? ` (locks: ${d.locks.join(', ')})` : ''}`);
}

export function ruleSentence(treatment) {
  if (!treatment || drawn(treatment)) return 'Write the art brief and pass the gallery critique before any UI page code.';
  if (treatment === 'utility') return 'Nothing to author before Step 3 (SKILL Step 3a: utility skips ahead); the tool is the first screen.';
  return 'Write the visual brief (asset/capture list) per SKILL Step 3a before any UI page code.';
}

// Under a typography or utility treatment the signature device is typographic: a drawn device would force an illustration the
// treatment (often a user directive) excludes. Returns the device to print and a note when it was replaced.
export function fitDevice(device, concept, treatment) {
  if ((treatment !== 'typography' && treatment !== 'utility') || (device && TECH_TREATMENT[device.technique] === 'typography')) return { device, note: null };
  const typo = concept?.devices?.find(d => d.technique === 'typographic');
  const dv = typo || { technique: 'typographic', what: '(synthesized: no drawn device under a typography/utility treatment; carry the concept in type, numerals, rules and layout)' };
  return { device: dv, note: device ? `treatment ${treatment} takes a typographic device; dropped drawn device ${device.technique}` : null };
}

// A directive that asks for black and white / monochrome while locking ink-on-paper: no accent, no tinted seed.
export const noAccent = (dossier, strategy) => strategy === 'ink-on-paper'
  && (dossier?.directives || []).some(d => /black\s*(and|&|\/)\s*white|monochrome|greyscale|grayscale/i.test(d?.text || ''));
