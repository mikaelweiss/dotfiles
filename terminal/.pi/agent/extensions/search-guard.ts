import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const SEARCH_CMD = /^\s*(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*(?:command\s+)?(?:rg|grep|egrep|fgrep|ugrep|ag|ast-grep|sg)\b/;
const GIT_GREP = /(?:^|[\n;&|(`]\s*|\$\(\s*|\bcommand\s+)git\s+(?:-C\s+\S+\s+)?grep\b/;
const QUOTED = /<<-?\s*['"]?(\w+)['"]?\n[\s\S]*?\n\s*\1\b|'[^']*'|"(?:\\.|[^"\\])*"/g;
const codeOnly = (cmd: string) => cmd.replace(QUOTED, " ");

const RETRY_NOTE =
  "[search-guard] Empty search result. This does not prove absence: ignore files, hidden files, " +
  "binary detection, and the 100-match cap all hide matches. Retry once with `rg -uuu -F 'needle' path` " +
  "in bash before concluding the text does not exist, and say which flags found it.";

function textOf(content: unknown): string {
  if (!Array.isArray(content)) return "";
  return content
    .map((c) => (c && typeof c === "object" && (c as { type?: string }).type === "text" ? String((c as { text?: string }).text ?? "") : ""))
    .join("\n");
}

const SHELL_TOOLS = new Set(["bash", "shell", "run_terminal_cmd", "terminal"]);
const GREP_TOOLS = new Set(["grep", "grep_search", "search"]);

function commandOf(input: unknown): string {
  const i = input as { command?: unknown; cmd?: unknown } | undefined;
  const c = i?.command ?? i?.cmd ?? "";
  return Array.isArray(c) ? c.map(String).join(" ") : String(c);
}

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event) => {
    if (SHELL_TOOLS.has(event.toolName.toLowerCase()) && GIT_GREP.test(codeOnly(commandOf(event.input)))) {
      return {
        block: true,
        reason: "git grep is blocked: it skips untracked files and nested repos and mangles non-ASCII paths. Use rg.",
      };
    }
  });

  pi.on("tool_result", async (event) => {
    const name = event.toolName.toLowerCase();
    const text = textOf(event.content).trim();
    const isGrepTool = GREP_TOOLS.has(name);
    const isBashSearch = SHELL_TOOLS.has(name) && SEARCH_CMD.test(commandOf(event.input));
    if (!isGrepTool && !isBashSearch) return;
    const body = text
      .replace(/\(no output\)/g, "")
      .replace(/Command exited with code \d+/g, "")
      .replace(/^Exit code:? \d+\s*/im, "")
      .trim();
    const empty = body === "" || body === "0" || /^No (matches|files) found/i.test(body);
    if (!empty) return;
    return { content: [...(Array.isArray(event.content) ? event.content : []), { type: "text", text: RETRY_NOTE }] };
  });
}
