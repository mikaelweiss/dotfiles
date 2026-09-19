#!/usr/bin/env python3
"""Em dash guard for Claude Code and Codex hooks.

PreToolUse: block a file write or a shell command that would put U+2014 into
text. The character stays legal as a search needle and in a substitution that
strips it, so finding and removing existing em dashes still works. A body that
carries the marker below is exempt, for the rare file that discusses the
character itself.
"""
import json
import re
import sys

EM = "—"
ALLOW_MARKER = "emdash-ok"

SHELL_WRAPPER = re.compile(r"^\s*(?:/\S*/)?(?:ba|z|da)?sh\s+-[a-z]*c\s+['\"]?")
SEARCH_CMD = re.compile(r"\b(?:rg|grep|egrep|fgrep|ugrep|ag|ast-grep|sg)\b")
PUBLISHING = re.compile(
    r"\bgit\s+(?:-C\s+\S+\s+)?(?:commit|tag|notes|merge|revert)\b"
    r"|\bgh\s+(?:pr|issue|release)\b"
)
STRIPPING = re.compile("|".join([
    r"s/[^/]*" + EM + r"[^/]*/",
    r"s\|[^|]*" + EM + r"[^|]*\|",
    r"s#[^#]*" + EM + r"[^#]*#",
    r"\btr\b[^\n]{0,20}" + EM,
    r"\.replace\(\s*[\"'][^\"']*" + EM,
]))

TEXT_FIELDS = ("content", "new_string", "new_source", "new_str", "file_text", "replace")

NOTE = (
    "[emdash-guard] Blocked: this text contains an em dash (U+2014). Replace it with a "
    "period, comma, colon, parentheses, or a plain hyphen, then retry. Searching for the "
    "character or stripping it with a substitution is allowed; writing one is not."
)


def command_text(tool_input):
    if isinstance(tool_input, str):
        return tool_input
    if isinstance(tool_input, dict):
        cmd = tool_input.get("command") or tool_input.get("cmd") or ""
        if isinstance(cmd, list):
            cmd = " ".join(str(c) for c in cmd)
        return SHELL_WRAPPER.sub("", str(cmd))
    return ""


def texts(tool_input):
    if isinstance(tool_input, str):
        yield tool_input
        return
    if not isinstance(tool_input, dict):
        return
    for key in TEXT_FIELDS:
        value = tool_input.get(key)
        if isinstance(value, str):
            yield value
    path = tool_input.get("file_path") or tool_input.get("path")
    if isinstance(path, str):
        yield path
    edits = tool_input.get("edits")
    if isinstance(edits, list):
        for edit in edits:
            if isinstance(edit, dict):
                for key in TEXT_FIELDS:
                    value = edit.get(key)
                    if isinstance(value, str):
                        yield value


def deny():
    print(json.dumps({
        "decision": "block",
        "reason": NOTE,
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": NOTE,
        },
    }))


def main():
    try:
        event = json.load(sys.stdin)
    except Exception:
        return
    if event.get("hook_event_name", "") != "PreToolUse":
        return
    tool_input = event.get("tool_input")

    if event.get("tool_name", "") == "Bash":
        cmd = command_text(tool_input)
        if EM not in cmd or ALLOW_MARKER in cmd:
            return
        if PUBLISHING.search(cmd):
            deny()
            return
        if SEARCH_CMD.search(cmd) or STRIPPING.search(cmd):
            return
        deny()
        return

    for text in texts(tool_input):
        if EM in text and ALLOW_MARKER not in text:
            deny()
            return


if __name__ == "__main__":
    main()
