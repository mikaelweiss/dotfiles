#!/usr/bin/env python3
"""Bridge Cursor path-scoped rules (.cursor/rules/*.mdc) to Claude Code.

Hook mode (default, PostToolUse on Edit/Write): reads the hook payload on
stdin, extracts edited file paths, matches them against each rule's glob
frontmatter, and emits additionalContext telling the model which rule files
to read. Each rule fires at most once per session.

Check mode: `rule-bridge.py --check <path>...` prints the rules matching the
given (prospective) paths as plain text. Used by the /plan skill during
discovery. Stateless.

The rule content itself is never duplicated here: the single source of truth
stays in .cursor/rules/, so Cursor and Claude Code can never drift.

Fails open: malformed input, no project rules dir, or no match means no
output and exit 0.
"""

import json
import os
import re
import sys
import tempfile

# Rules whose guidance is repo-wide (no meaningful path scope) and already
# carried by the root CLAUDE.md; a per-edit reminder would be pure noise.
SKIP = {
    "angular-modern",
    "architecture-principles",
    "clean-code",
    "domain-model-boundary",
    "no-any-types",
    "long-running-commands",
    "ui-copy",
}


def split_globs(value):
    """Split a comma-separated glob line, respecting {a,b} alternation."""
    parts, depth, cur = [], 0, ""
    for ch in value:
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append(cur.strip())
            cur = ""
        else:
            cur += ch
    if cur.strip():
        parts.append(cur.strip())
    return [p.strip("\"'") for p in parts if p.strip("\"'")]


def glob_to_regex(pattern):
    i, out, n = 0, "", len(pattern)
    while i < n:
        ch = pattern[i]
        if ch == "*":
            if pattern[i : i + 3] == "**/":
                out += "(?:.*/)?"
                i += 3
            elif pattern[i : i + 2] == "**":
                out += ".*"
                i += 2
            else:
                out += "[^/]*"
                i += 1
        elif ch == "?":
            out += "[^/]"
            i += 1
        elif ch == "{":
            j = pattern.find("}", i)
            if j == -1:
                out += re.escape(ch)
                i += 1
            else:
                opts = pattern[i + 1 : j].split(",")
                out += "(?:" + "|".join(re.escape(o) for o in opts) + ")"
                i = j + 1
        else:
            out += re.escape(ch)
            i += 1
    return re.compile("^" + out + "$")


def parse_frontmatter(text):
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}
    meta, globs, in_globs = {}, [], False
    for line in lines[1:]:
        if line.strip() == "---":
            break
        if in_globs:
            item = re.match(r"\s*-\s*(.+)", line)
            if item:
                globs.append(item.group(1).strip().strip("\"'"))
                continue
            in_globs = False
        if line.startswith("description:"):
            meta["description"] = line.split(":", 1)[1].strip()
        elif line.startswith("globs:"):
            rest = line.split(":", 1)[1].strip()
            if rest:
                globs.extend(split_globs(rest))
            else:
                in_globs = True
    meta["globs"] = globs
    return meta


def load_rules(root):
    rules_dir = os.path.join(root, ".cursor", "rules")
    if not os.path.isdir(rules_dir):
        return []
    rules = []
    for fname in sorted(os.listdir(rules_dir)):
        if not fname.endswith(".mdc"):
            continue
        name = fname[: -len(".mdc")]
        if name in SKIP:
            continue
        try:
            with open(os.path.join(rules_dir, fname), encoding="utf-8") as fh:
                meta = parse_frontmatter(fh.read())
        except OSError:
            continue
        patterns = [glob_to_regex(g) for g in meta.get("globs", [])]
        if patterns:
            rules.append((name, meta.get("description", ""), patterns))
    return rules


def match_rules(rules, rel_paths):
    matched = []
    for name, description, patterns in rules:
        if any(p.match(rel) for p in patterns for rel in rel_paths):
            matched.append((name, description))
    return matched


def rel_paths_for(root, paths):
    rels = []
    for p in paths:
        rel = os.path.relpath(p, root) if os.path.isabs(p) else p
        if not rel.startswith(".."):
            rels.append(rel)
    return rels


def extract_paths(obj, found):
    if isinstance(obj, dict):
        for key, value in obj.items():
            if key in ("path", "file_path") and isinstance(value, str):
                found.append(value)
            else:
                extract_paths(value, found)
    elif isinstance(obj, list):
        for value in obj:
            extract_paths(value, found)


def check_mode(paths):
    root = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    matched = match_rules(load_rules(root), rel_paths_for(root, paths))
    for name, description in matched:
        print(f"- .cursor/rules/{name}.mdc: {description}")
    if not matched:
        print("(no path-scoped rules match)")


def hook_mode():
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return
    root = os.environ.get("CLAUDE_PROJECT_DIR") or payload.get("cwd") or os.getcwd()
    session = payload.get("session_id", "nosession")

    paths = []
    extract_paths(payload.get("tool_input", {}), paths)
    if not paths:
        return

    matched = match_rules(load_rules(root), rel_paths_for(root, paths))
    if not matched:
        return

    state_path = os.path.join(
        tempfile.gettempdir(), f"claude-rule-bridge-{session}"
    )
    seen = set()
    try:
        with open(state_path, encoding="utf-8") as fh:
            seen = set(fh.read().split())
    except OSError:
        pass

    fresh = [(n, d) for n, d in matched if n not in seen]
    if not fresh:
        return

    try:
        with open(state_path, "a", encoding="utf-8") as fh:
            for name, _ in fresh:
                fh.write(name + "\n")
    except OSError:
        pass

    lines = "\n".join(f"- .cursor/rules/{n}.mdc: {d}" for n, d in fresh)
    body = (
        "RULE REMINDER: the file(s) just edited are governed by repo rules "
        "not yet surfaced this session. Read each rule file before "
        "continuing and apply it to this change:\n" + lines
    )
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PostToolUse",
                    "additionalContext": body,
                }
            }
        )
    )


def main():
    try:
        if len(sys.argv) > 1 and sys.argv[1] == "--check":
            check_mode(sys.argv[2:])
        else:
            hook_mode()
    except Exception:
        pass
    sys.exit(0)


if __name__ == "__main__":
    main()
