// fold-gates.mjs — which first-viewport rows are gated for which hero treatment (vary SKILL Step 3a router).
// A null gate makes the row INFO ("informational for treatment <t>"); the measures still print.
export const TREATMENTS = ['scene', 'pattern', 'photography', 'product-ui', 'typography', 'data-visual', 'utility'];
export const MODES = ['persuade', 'experience', 'operate', 'read'];
export const OFF = { cov: null, detail: null, plates: null, inScene: false, card: null, bleed: false, depth: false, dead: null, artDown: null, platesSize: null };
export const GATES = {
  scene: { cov: [0.55, 0.45], detail: 50, plates: 4, inScene: true, card: 'all', bleed: true, depth: true, dead: 0.2, artDown: 0.6, platesSize: 0.5 },
  pattern: { ...OFF, cov: [0.55, 0.45], inScene: true, card: 'glass', bleed: true },
  photography: { ...OFF, cov: [0.4, 0.35] },
  'product-ui': { ...OFF, cov: [0.25, 0.2] },
  'data-visual': { ...OFF, cov: [0.3, 0.25], detail: 20 },
  typography: { ...OFF },
  utility: { ...OFF },
};
// default is neutral: a drawn scene is a choice, so scene rows gate only on an explicit --treatment scene
export const defaultTreatment = mode => (mode === 'persuade' || mode === 'experience' ? 'typography' : 'utility');
