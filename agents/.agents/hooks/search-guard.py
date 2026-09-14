#!/usr/bin/env python3
"""Search guard for Claude Code and Codex hooks.

PreToolUse: block `git grep`.
PostToolUse: when a search command returned nothing, tell the model to retry
with ignore files, hidden files, and binary files enabled before concluding absence.
"""
import json
import re
import sys

SHELL_WRAPPER = re.compile(r"^\s*(?:/\S*/)?(?:ba|z|da)?sh\s+-[a-z]*c\s+['\"]?")
SEARCH_CMD = re.compile(
    r"^\s*(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*(?:command\s+)?"
    r"(?:rg|grep|egrep|fgrep|ugrep|ag|ast-grep|sg)\b"
)
GIT_GREP = re.compile(r"(?:^|[\n;&|(`]\s*|\$\(\s*|\bcommand\s+)git\s+(?:-C\s+\S+\s+)?grep\b")
QUOTED = re.compile(
    r"<<-?\s*['\"]?(\w+)['\"]?\n[\s\S]*?\n\s*\1\b"
    r"|'[^']*'"
    r"|\"(?:\\.|[^\"\\])*\""
)


def code_only(cmd):
    return QUOTED.sub(" ", cmd)
NOISE_KEYS = {"exit_code", "exitCode", "duration_ms", "durationMs", "interrupted",
              "isImage", "is_image", "backgroundTaskId", "returnCodeInterpretation"}

RETRY_NOTE = (
    "[search-guard] Empty search result. This does not prove absence: ignore files, "
    "hidden files, binary detection, and shell globbing all hide matches. Retry once with "
    "`rg -uuu -F 'needle' path` (or `command grep -r`) before concluding the text does not exist, "
    "and say which flags found it."
)
GIT_GREP_NOTE = (
    "[search-guard] `git grep` is blocked: it skips untracked files and nested repos and "
    "mangles non-ASCII paths. Use `rg` instead (`rg -uuu -F` to include ignored and hidden files)."
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


def output_text(resp):
    if resp is None:
        return ""
    if isinstance(resp, str):
        return re.sub(r"^Exit code \d+\s*", "", resp).strip()
    if isinstance(resp, list):
        return "\n".join(output_text(r) for r in resp)
    if isinstance(resp, dict):
        for key in ("stdout", "output", "aggregated_output", "formatted_output", "content", "text"):
            if key in resp:
                return output_text(resp[key])
        return "\n".join(output_text(v) for k, v in resp.items() if k not in NOISE_KEYS)
    return ""


def main():
    try:
        event = json.load(sys.stdin)
    except Exception:
        return
    hook = event.get("hook_event_name", "")
    cmd = command_text(event.get("tool_input"))
    if not cmd:
        return

    if hook == "PreToolUse":
        if GIT_GREP.search(code_only(cmd)):
            print(json.dumps({
                "decision": "block",
                "reason": GIT_GREP_NOTE,
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": GIT_GREP_NOTE,
                },
            }))
        return

    if hook == "PostToolUse":
        if not SEARCH_CMD.search(cmd) and not GIT_GREP.search(code_only(cmd)):
            return
        out = output_text(event.get("tool_response")).strip()
        if out in ("", "0"):
            print(json.dumps({
                "hookSpecificOutput": {
                    "hookEventName": "PostToolUse",
                    "additionalContext": RETRY_NOTE,
                }
            }))


if __name__ == "__main__":
    main()
