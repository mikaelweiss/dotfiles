import type { Plugin } from "@opencode-ai/plugin"

const SEARCH_CMD = /^\s*(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*(?:command\s+)?(?:rg|grep|egrep|fgrep|ugrep|ag|ast-grep|sg)\b/
const GIT_GREP = /(?:^|[\n;&|(`]\s*|\$\(\s*|\bcommand\s+)git\s+(?:-C\s+\S+\s+)?grep\b/
const QUOTED = /<<-?\s*['"]?(\w+)['"]?\n[\s\S]*?\n\s*\1\b|'[^']*'|"(?:\\.|[^"\\])*"/g
const codeOnly = (cmd: string) => cmd.replace(QUOTED, " ")

const RETRY_NOTE =
  "\n\n[search-guard] Empty search result. This does not prove absence: ignore files, hidden files, " +
  "binary detection, and result caps all hide matches. Retry once with `rg -uuu -F 'needle' path` in bash " +
  "before concluding the text does not exist, and say which flags found it."

export const SearchGuard: Plugin = async () => ({
  "tool.execute.before": async (input, output) => {
    if (input.tool === "bash" && GIT_GREP.test(codeOnly(String(output.args?.command ?? "")))) {
      throw new Error(
        "git grep is blocked: it skips untracked files and nested repos and mangles non-ASCII paths. Use rg.",
      )
    }
  },
  "tool.execute.after": async (input, output) => {
    const text = output.output ?? ""
    if (input.tool === "grep" && /^No files found/.test(text.trim())) {
      output.output = text + RETRY_NOTE
      return
    }
    if (input.tool === "bash" && SEARCH_CMD.test(String(input.args?.command ?? ""))) {
      const body = text.replace(/^Exit code \d+\s*/m, "").trim()
      if (body === "" || body === "0") output.output = text + RETRY_NOTE
    }
  },
})
