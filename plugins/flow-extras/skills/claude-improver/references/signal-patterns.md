# Signal Patterns — What Counts as Real Pain

Load this reference during Phase 2 (Synthesis) to filter findings.

---

## The Three Rules of Signal vs Noise

1. **Frequency beats severity.** A mildly annoying thing that happens 30×/month deserves automation more than a catastrophic thing that happens twice a year.
2. **Adoption requires zero-friction invocation.** The best recommendation dies if the command name doesn't map to how the user already thinks.
3. **Every recommendation has a cost.** Max 5 recommendations per run. Beyond 7, decision fatigue causes the entire list to be dismissed.

---

## 8 Signal Patterns (Real Pain)

### Signal 1: Shell History Clusters (strongest signal)

**Look for:** Commands appearing 3+ times in 30 days with identical/near-identical args, especially multi-pipe chains.

**Paths:**
- Fish: `~/.local/share/fish/fish_history`
- Bash: `~/.bash_history`
- Zsh: `~/.zsh_history` or `~/.histfile`
- Atuin: `atuin search --limit 10000 | sort | uniq -c | sort -rn`

**Grep-equivalent:**
```bash
# Fish history has `- cmd:` lines; extract and count
grep '^- cmd:' ~/.local/share/fish/fish_history | sort | uniq -c | sort -rn | head -30
```

**Threshold:** 3+ occurrences of a command sequence with 2+ pipes/flags in 30 days.

**Why it's the strongest signal:** Shell history captures what the user actually does, not what they say. Objective, not inferred.

### Signal 2: Makefile / script targets wrapping multi-step sequences

**Look for:** `Makefile`, `package.json` scripts, `justfile`, `Taskfile.yaml`, `flake.nix` apps with targets running >2 commands.

**Stronger signal:** Targets with comments like `# Run before pushing`, `# Don't forget step 3`, `# Required after migration`.

**Why it signals:** The user already decided the sequence was worth encoding. The pain is real. Just hasn't been brought into Claude's context.

**Anti-pattern:** Targets that alias single commands (`make test = npm test`) — no Claude help needed.

### Signal 3: TODO/FIXME comments with automation intent or emotional language

**Look for:**
```
TODO.*automat|TODO.*script|FIXME.*manual|# ugh|# hate|# why|# don.t forget|# remember to|# step [0-9]
```

**Why it signals:** Emotional comments in 3-year-old files mean persistent pain. The author expected automation would eventually arrive.

### Signal 4: README "Gotchas" / "Before You Start" / "Common Issues" sections

**Look for:** README sections with imperative-heavy bullet lists. Count lines starting with "Run", "Install", "Set", "Make sure", "Don't forget".

**Calibration:** If README setup section > 20 lines, there is almost certainly a hook candidate in there.

**Stronger signal:** The ratio of imperative commands to total README length. A 200-line README with 40 imperatives = badly automated workflow.

### Signal 5: CI/CD retry patterns

**Look for in `.github/workflows/*.yml`, `.circleci/config.yml`, `Jenkinsfile`:**
- `retry:` directives with count > 1
- `continue-on-error: true` on test steps
- Explicit `sleep 30` / `sleep 60` between steps
- Commented-out "sometimes needed" steps

**Why it signals:** CI retry logic is explicit documentation of flakiness. A known pain point.

### Signal 6: Co-change coupling anomalies

**Look for:** File pairs that change together at >60% rate across 10+ commits.

**Command:**
```bash
git log --name-only --pretty=format: --since="90 days ago" \
  | awk 'NF' | sort | uniq -c | sort -rn | head -50
```

Then pair-count:
```bash
git log --name-only --since="90 days ago" | awk '/./{print}' \
  | paste -sd " " - | tr " " "\n" | ...
```

**Why it signals:** Files that always change together signal missing abstraction AND a hook candidate (PostToolUse on file A → remind about file B).

**Threshold:** Co-change rate >60% across 10+ commits.

### Signal 7: Duplicate snippets across 3+ files

**Look for:** 10+ identical/near-identical line blocks in 3+ files. Rule of Three applies directly.

**Detection:**
```bash
# Poor man's duplication check
find . -name "*.py" -exec md5sum {} \; | awk '{print $1}' | sort | uniq -c | sort -rn
# Or use duplication-detector tools: jscpd, pmd-cpd
```

**Why it signals:** User writes the same code multiple times because they don't have a generator/template.

### Signal 8: Temporal hotspots (high-churn files)

**Look for:** Files with many commits in last 30-60 days.

**Command:**
```bash
git log --since="60 days ago" --name-only --pretty=format: | sort | uniq -c | sort -rn | head -20
```

**Differentiate:**
- High-churn + growing size = active development (neutral)
- High-churn + stable/shrinking = iteratively fixed = pain signal

---

## 6 Anti-Signals (Not Real Pain)

### Anti-Signal 1: One-time setup commands

README sequences like `brew install terraform awscli kubectl && aws configure`. Runs once per machine. Automation doesn't pay back cost. **Test:** Would the user run this >2 times in their career? If not, don't recommend.

### Anti-Signal 2: Things already handled by existing tools

The #1 analyzer failure. Before recommending anything, check:
- `.pre-commit-config.yaml`
- `husky` in devDependencies
- `lefthook.yml`
- `.git/hooks/` non-empty
- Existing `.claude/` artifacts
- Existing Makefile/justfile targets
- Existing aliases/abbreviations

**If equivalent exists: DROP THE RECOMMENDATION.**

### Anti-Signal 3: Pleasurably manual tasks

Tasks where the manual process provides value beyond the output — the act of doing forces useful reflection.

Examples: writing commit messages (forces reflection), choosing dependencies to upgrade (requires judgment about breaking changes), code review comments, sprint planning.

**Detection heuristic:** If the output is a judgment/communication artifact rather than a mechanical transformation, it's likely pleasurably manual.

### Anti-Signal 4: Rarely-triggered commands (<1/week or <10/year)

A complex 5-step deployment running once/quarter is not worth a slash command. User won't remember it exists.

**Exception:** Rare BUT high-consequence (production deploys, DB migrations) → automate with guardrails (dry-run, confirmation).

### Anti-Signal 5: Framework-handled patterns

Modern frameworks already automate:
- Next.js/Angular/Nx → `generate` commands exist
- FastAPI/tRPC → OpenAPI docs auto-generated
- Rails/Django/Prisma → migration tooling built-in

**Check:** `package.json` for `"generate":` scripts, framework docs, existing generators BEFORE suggesting generators.

### Anti-Signal 6: Structure-only inferences

"You have 15 files in `utils/` — consider adding a code-organizer skill." This ignores that the user may have organized exactly how they want. Structure tells you what the project does, not where the pain is.

**Pain-first analysis > structure-first analysis.**

---

## The "Would I Invoke This?" Test

Drop any recommendation where the user would answer "no" to these:

| Criterion | Test |
|-----------|------|
| **Naming** | Does the name match the word the user would naturally say? |
| **Trigger clarity** | Can the user articulate in one sentence when they'd use it? |
| **30-second value** | Will it produce something immediately, or demand more work? |
| **Memory decay** | Will they remember it after 2 weeks? |
| **Duplicate check** | Does an existing tool already do this? |
| **Dependency acceptance** | Does it require installing new stuff? |

---

## Cost-of-Suggestion Framework

Every recommendation has a cost. Only surface if Value > Cost.

| Cost | ~Amount | Who pays |
|------|---------|----------|
| Reading | 5-15s per item | User (every time) |
| Evaluating | Same regardless of quality | User (every time) |
| Installing | 0-60+ min | User (once, if accepted) |
| Maintenance | Often hidden, ongoing | User (forever, if accepted) |
| Trust tax | Multiplier on future suggestions | User (permanent if wrong) |

**The trust-tax rule:** A wrong recommendation doesn't just waste evaluation time — it degrades trust in ALL future recommendations. Security teams that get 100 low-confidence alerts stop responding to the 2 real ones. Same pattern applies here.

**Hard rules:**
- Max 5 recommendations per run
- Each must include a one-line "maintenance cost" note
- No recommendation costing >30 min to install should be surfaced unless it saves >10 min/week
