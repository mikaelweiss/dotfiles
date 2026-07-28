---
name: ste-writing
description: Rewrite prose (docs, READMEs, PR descriptions, commit bodies, error messages, release notes, code comments; never code itself) into ASD-STE100 Simplified Technical English to remove "AI slop". Use when asked to make writing not sound like AI, make docs plain or clear, enforce a controlled writing style, or write technical documentation that reads human. Two modes: strict (procedures, safety, error messages) and flavored (general prose).
user-invocable: true
---

# ste-writing

Write prose in ASD-STE100 Simplified Technical English. The default is every run of prose you produce, in every channel. That covers chat replies, code comments, docstrings, commit titles and bodies, pull-request and issue and review text, READMEs and docs, error messages, log messages, CLI help and usage text, release notes, plan documents, user-facing string literals, generated docs, and Slack and email messages.

Four exclusions, and nothing else: code itself, identifiers, command syntax, and text you reproduce verbatim from another source. Marketing copy and essays are also out of scope, because STE strips voice on purpose. If you are unsure whether a surface counts, it counts.

The compact form of these rules lives in the Voice section of `~/.claude/CLAUDE.md` and is always loaded, so chat replies follow it without this skill. Load this skill when you want the full rule set, the mode split, and the lint loop.

## Rules

WORDS
- Use one name for one thing. Do not call the same item by two different names.
- Use the short common word: start (not begin/commence/initiate), use (not utilize/leverage), help (not facilitate), make sure (not ensure), before (not prior to), after (not subsequent to), about (not regarding/concerning), get (not obtain/acquire), show (not demonstrate), also (not additionally/furthermore/moreover).
- Give each word one meaning. "fall" means to move down, not to decrease.
- No marketing adjectives: seamless, robust, powerful, cutting-edge, effortless, world-class, next-generation, revolutionary.
- American spelling.

VERBS
- Active voice. "the parser reads the file", not "the file is read by the parser".
- Use a verb for an action. "analyze the log", not "perform an analysis of the log".
- No stacked auxiliaries. Not "it is important to note that this may help to improve". Write "this improves X".
- No "-ing" main verb where a simple tense works.

SENTENCES
- One instruction per sentence. Max 20 words for an instruction, max 25 for a description.
- No contractions in written artifacts. Contractions are fine in chat replies. Use articles: a, an, the, this, these.

PUNCTUATION
- No semicolons. Write two sentences.
- No em dashes and no en dashes. This is a house rule from CLAUDE.md, not from STE. Use a period, comma, colon, parentheses, or a plain hyphen.

STRUCTURE
- One topic per paragraph, max six sentences. For steps, use a numbered vertical list, one action per item, imperative form. Put a condition before its command.

Write only the requested text. No preamble, no summary, no closing remarks.

## Modes

- **strict**: procedures, runbooks, safety text, error messages, code comments. Apply every rule and both length caps. A comment is read by a person who is confused, which is the same situation as an error message.
- **flavored**: general prose such as READMEs, PR descriptions, and docs. Apply the sentence, paragraph, active-voice, and no-phrasal-verb discipline. Relax the 900-word dictionary lockdown so the text keeps enough range to read naturally.

Default to flavored. Switch to strict when the text tells a person what to do, or when a person reads it while something is broken.

## The lint loop

The score is the signal, not your own judgment about the draft. Run it:

1. Write the draft to a file.
2. Lint it: `python3 ~/.claude/skills/ste-writing/ste-lint.py <file>`
3. Read the `violations` breakdown. Fix the named categories in the draft.
4. Lint again. The score must go down.
5. Repeat until `total_per100w` is at or under the target, or until a further rewrite would change the meaning.

Targets, in violations per 100 words:

| Mode | Target |
|---|---|
| strict | 1.0 or lower |
| flavored | 2.0 or lower |

For reference, an unguided model draft scores about 3.5 to 4.4.

`em_dash` and `long_paragraph` are counted in the total. A single unavoidable violation is acceptable when fixing it would make the text wrong. Say which one you kept and why.

## Self-lint (before returning text, even when you skip the linter)

1. Any sentence over 20 words? Split it.
2. Any semicolon, em dash, or en dash? Replace it.
3. Any contraction? Expand it.
4. Any passive voice with a known actor? Make it active.
5. Any "-ing" main verb, nominalization ("perform an analysis"), or phrasal verb ("spin up")? Replace it with a plain verb.
6. Same thing named two ways? Pick one name.

## Limits

The rules above are mechanical and lintable. They fix the FORM of slop. Full STE also needs human judgment, such as the right technical noun and whether a sentence makes good sense. A checker cannot certify that. This skill cannot make a hollow paragraph true, and a clean score on an empty claim is still an empty claim.

Source standard, free but copyrighted (do not paste it in full): https://asd-ste100.org
