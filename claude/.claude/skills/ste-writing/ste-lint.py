#!/usr/bin/env python3
"""Heuristic ASD-STE100 "anti-slop" linter. Deterministic; no dependencies.

Score is violations per 100 words. Lower is cleaner. The signal is the DELTA
between a draft and its rewrite, not the absolute number.

    python3 ste-lint.py draft.md            # one file, table row
    python3 ste-lint.py 'docs/**/*.md'      # glob, one row per file
    cat draft.md | python3 ste-lint.py      # stdin, full JSON breakdown
    python3 ste-lint.py --json draft.md     # force JSON breakdown
    python3 ste-lint.py --max 2.0 draft.md  # exit 1 if any file scores over 2.0

Not a certified STE checker. The judgment rules of ASD-STE100 need a human.
This covers the mechanical subset, which is where the slop lives.

Adapted from https://github.com/woosal1337/blog/tree/main/videos/ep01-the-cure-for-ai-slop
Local change: em and en dashes count as violations (CLAUDE.md house rule),
measured on code-stripped prose like every other check.
"""

import re, sys, json, glob, os

MARKETING = ["seamless","seamlessly","robust","powerful","cutting-edge","effortless","effortlessly",
    "world-class","next-generation","revolutionary","blazing","lightning-fast","elegant","delightful",
    "turnkey","best-in-class","state-of-the-art","game-changing","first-class","battle-tested",
    "enterprise-grade","supercharge","unlock","unleash","empower","empowers"]
BANNED = ["begin","begins","commence","commences","initiate","initiates","originate",
    "utilize","utilizes","utilizing","leverage","leverages","leveraging","facilitate","facilitates",
    "ensure","ensures","ensuring","prior to","subsequent to","obtain","obtains","acquire","acquires",
    "demonstrate","demonstrates","additionally","furthermore","moreover","comprehensive","comprehensively",
    "utilization","aforementioned","henceforth","therein","whilst","amongst","numerous","myriad","plethora",
    "in order to","a variety of","in the event that","due to the fact that","it is important to note"]
PHRASAL = ["spin up","spin down","reach out","dive into","dives into","diving into","kick off","kicks off",
    "roll out","rolls out","tear down","ramp up","circle back","drill down","spun up","reaching out"]
MODAL_HEDGE = ["it is important to note","it should be noted","it is worth noting","please note that",
    "as mentioned","as noted above"]
BE = r"(?:am|is|are|was|were|be|been|being)"
PP_IRREG = r"(?:done|made|sent|read|built|kept|held|set|put|run|written|shown|given|taken|found|got|gotten|seen|known|thrown|drawn)"


def strip_code(t):
    t = re.sub(r"```.*?```", " ", t, flags=re.S)
    t = re.sub(r"`[^`]*`", " ", t)
    return t


def sentences(text):
    out = []
    for line in text.split("\n"):
        s = line.strip()
        if not s: continue
        s = re.sub(r"^\s*#{1,6}\s*", "", s)
        s = re.sub(r"^\s*(?:[-*+]|\d+[.)])\s+", "", s)
        if not s: continue
        parts = re.split(r"(?<=[.!?:])\s+(?=[A-Z0-9\"'\-])", s)
        for p in parts:
            p = p.strip()
            if p: out.append(p)
    return out


def wc(s):
    return len([w for w in re.findall(r"[A-Za-z0-9][A-Za-z0-9'\-/]*", s)])


def count_ci(text, phrases):
    n = 0; hits = []
    low = text.lower()
    for ph in phrases:
        for m in re.finditer(r"(?<![a-z])" + re.escape(ph) + r"(?![a-z])", low):
            n += 1; hits.append(ph)
    return n, hits


def lint(text):
    raw = text
    text = strip_code(text)
    sents = sentences(text)
    words = sum(wc(s) for s in sents) or 1
    v = {}
    longs = [(wc(s), s) for s in sents if wc(s) > 20]
    v["long_sentence(>20w)"] = len(longs)
    v["semicolon"] = text.count(";")
    v["em_or_en_dash"] = text.count("—") + text.count("–")
    v["contraction"] = len(re.findall(r"\b\w+['’](?:t|re|ve|ll|d|s|m)\b", text))
    v["passive_voice"] = len(re.findall(rf"\b{BE}\s+(?:\w+ed|{PP_IRREG})\b", text, re.I))
    v["ing_main_verb"] = len(re.findall(rf"\b{BE}\s+\w+ing\b", text, re.I))
    v["nominalization"] = len(re.findall(r"\b(?:perform(?:s|ed)?|conduct(?:s|ed)?|provide(?:s|d)?|carry out|carries out|make use of|makes use of)\b", text, re.I)) + len(re.findall(r"\b\w{4,}(?:tion|ment|ance|ence)\s+of\b", text, re.I))
    v["phrasal_verb"], _ = count_ci(text, PHRASAL)
    v["banned_word"], bh = count_ci(text, BANNED)
    v["marketing_adjective"], mh = count_ci(text, MARKETING)
    v["modal_hedge"], _ = count_ci(text, MODAL_HEDGE)
    paras = [p for p in re.split(r"\n\s*\n", raw) if p.strip()]
    v["long_paragraph(>6s)"] = sum(1 for p in paras if len(sentences(strip_code(p))) > 6)
    total = sum(v.values())
    return {
        "words": words, "sentences": len(sents),
        "violations": {k: n for k, n in v.items() if n},
        "total": total,
        "total_per100w": round(total * 100.0 / words, 2),
        "longest_sentence_words": (max(longs)[0] if longs else max((wc(s) for s in sents), default=0)),
        "sample_marketing": list(dict.fromkeys(mh))[:6],
        "sample_banned": list(dict.fromkeys(bh))[:6],
    }


def main(argv):
    as_json = False
    ceiling = None
    files = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--json":
            as_json = True
        elif a == "--max":
            i += 1
            ceiling = float(argv[i])
        elif a.startswith("--max="):
            ceiling = float(a.split("=", 1)[1])
        else:
            files.append(a)
        i += 1

    if not files:
        r = lint(sys.stdin.read())
        print(json.dumps(r, indent=2))
        return 1 if ceiling is not None and r["total_per100w"] > ceiling else 0

    expanded = []
    for f in files:
        expanded += sorted(glob.glob(f, recursive=True)) if any(c in f for c in "*?[") else [f]

    worst = 0.0
    for f in expanded:
        with open(f) as fh:
            r = lint(fh.read())
        worst = max(worst, r["total_per100w"])
        if as_json or len(expanded) == 1:
            print(json.dumps({"file": f, **r}, indent=2))
        else:
            print(f"{os.path.basename(f):32} words={r['words']:4d} "
                  f"total={r['total']:3d} per100w={r['total_per100w']:6.2f}")

    return 1 if ceiling is not None and worst > ceiling else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
