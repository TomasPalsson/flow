// Sibling isolation for dependency-cruiser, for design.md row 4 in a TypeScript repo.
// A Python repo needs import-linter instead; the pattern is the same.
//
// MERGE this into an existing .dependency-cruiser.* file (add the two rules to
// its `forbidden` array and keep its `options`), and never overwrite a config
// the repo already has: it holds rules someone else relies on.
//
// Depth decides privacy. A module's root files are its entry points and stay
// importable. Anything in a subfolder is private. One back-reference ($1) states
// "siblings stay out of each other" once, for every module, so there are no
// pairwise rules to keep in step as modules are added.
//
// Set ROOT to the directory whose immediate children are the modules.

const ROOT = "src/modules";
const INTERNALS = `^${ROOT}/[^/]+/[^/]+/`;

/** @type {import('dependency-cruiser').IConfiguration} */
module.exports = {
  forbidden: [
    {
      name: "modules-use-entry-points-from-outside",
      comment: "Code outside the modules may import a module's root files, never its subfolders.",
      severity: "error",
      from: { pathNot: `^${ROOT}/` },
      to: { path: INTERNALS },
    },
    {
      name: "siblings-stay-out-of-each-others-internals",
      comment: "A module may use its own internals; other modules only through their entry points.",
      severity: "error",
      from: { path: `^${ROOT}/([^/]+)/` },
      to: { path: INTERNALS, pathNot: `^${ROOT}/$1/` },
    },
  ],
  options: {
    doNotFollow: { path: "node_modules" },
    tsConfig: { fileName: "tsconfig.json" },
  },
};

// Credit: adapted from mattpocock/skills skills/in-progress/setup-ts-deep-modules/dependency-cruiser.config.cjs @ 49dd158 (MIT).
