#!/usr/bin/env python3
"""skills-lint-collisions.py: report skill descriptions that read alike.

Called by skills-lint-frontmatter.py for `skills-lint --collisions`. Stemmed
TF-IDF cosine over the description of every SKILL.md under the given dirs;
pairs at 0.75 or more are listed, pairs at 0.5 or more are counted. A report
only: it always exits 0 and is never wired into a hook or a gate.

Credit: adapted from addyosmani/agent-skills scripts/run-evals.js @ 1be8e34 (MIT).
"""
import math
import re

STOP = set("""a an and are as at be but by can for from has have how if in into is it its
of on or not use used using when whenever where which while with without that the this
these those to than then they their them you your user users asks ask says say also
any all each every more most other some such only just will would should must may
skill skills claude code agent agents about via per""".split())


def stem(w):
    for suf in ("ations", "ation", "ingly", "ings", "ing", "edly", "ed", "ies", "es", "s", "ly"):
        if w.endswith(suf) and len(w) - len(suf) >= 3:
            return w[: -len(suf)] + ("y" if suf == "ies" else "")
    return w


def tokens(desc):
    return [stem(w) for w in re.findall(r"[a-z][a-z0-9]+", desc.lower()) if w not in STOP]


def collisions(roots, fm):
    docs = []
    for root in roots:
        for path in fm.find_docs(root)[0]:
            entries = fm.split_frontmatter(fm.read(path))
            desc = fm.parse_fields(entries)[0].get("description", (0, ""))[1] if entries else ""
            if desc:
                docs.append((path, tokens(desc)))
    df = {}
    for _, toks in docs:
        for t in set(toks):
            df[t] = df.get(t, 0) + 1
    n = len(docs)
    vecs = []
    for _, toks in docs:
        tf = {}
        for t in toks:
            tf[t] = tf.get(t, 0) + 1
        v = {t: c * (math.log((1 + n) / (1 + df[t])) + 1) for t, c in tf.items()}
        norm = math.sqrt(sum(x * x for x in v.values())) or 1.0
        vecs.append({t: x / norm for t, x in v.items()})
    hits, mild = [], 0
    for i in range(n):
        for j in range(i + 1, n):
            a, b = vecs[i], vecs[j]
            s = sum(x * b.get(t, 0.0) for t, x in a.items())
            if s >= 0.75:
                hits.append((s, docs[i][0], docs[j][0]))
            elif s >= 0.5:
                mild += 1
    for s, a, b in sorted(hits, reverse=True):
        print("COLLISION %.2f %s %s" % (s, a, b))
    print("collisions: %d pair(s) >= 0.75, %d pair(s) >= 0.5 across %d skills" % (len(hits), mild, n))
    return 0
