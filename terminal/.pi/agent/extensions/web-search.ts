import { Type } from "typebox";
import type { ExtensionAPI, ExtensionContext } from "@mariozechner/pi-coding-agent";
import {
  truncateHead,
  DEFAULT_MAX_BYTES,
  DEFAULT_MAX_LINES,
} from "@mariozechner/pi-coding-agent";
import { join } from "node:path";
import { homedir } from "node:os";
import { readFileSync, writeFileSync } from "node:fs";

const BRAVE_SEARCH_URL = "https://api.search.brave.com/res/v1/web/search";
const FIREWORKS_URL = "https://api.fireworks.ai/inference/v1/chat/completions";
const FILTER_MODEL = "accounts/fireworks/models/minimax-m2p7";

function getAuthPath(): string {
  return join(homedir(), ".pi/agent/auth.json");
}

function readAuth(): Record<string, any> {
  try {
    return JSON.parse(readFileSync(getAuthPath(), "utf8"));
  } catch {
    return {};
  }
}

function saveKeyToAuth(provider: string, key: string): void {
  const auth = readAuth();
  auth[provider] = { type: "api_key", key };
  writeFileSync(getAuthPath(), JSON.stringify(auth, null, 2) + "\n");
}

function getKey(provider: string, envVar: string): string {
  const fromEnv = process.env[envVar] ?? "";
  if (fromEnv) return fromEnv;
  return readAuth()[provider]?.key ?? "";
}

async function ensureKey(
  provider: string,
  envVar: string,
  signupUrl: string,
  ctx: ExtensionContext
): Promise<string> {
  let key = getKey(provider, envVar);
  if (key) return key;

  ctx.ui.notify(
    `${provider} API key required. Sign up at ${signupUrl}`,
    "warning"
  );

  const input = await ctx.ui.input(
    `${provider} API key`,
    `Paste your ${provider} key here...`
  );

  if (!input?.trim()) {
    throw new Error(`${provider} API key is required. Sign up at ${signupUrl}`);
  }

  saveKeyToAuth(provider, input.trim());
  ctx.ui.notify(`${provider} key saved to ~/.pi/agent/auth.json`, "info");
  return input.trim();
}

interface BraveResult {
  title: string;
  url: string;
  description: string;
  age?: string;
}

async function braveSearch(
  query: string,
  braveKey: string,
  count: number,
  signal?: AbortSignal
): Promise<BraveResult[]> {
  const params = new URLSearchParams({ q: query, count: String(count) });
  const res = await fetch(`${BRAVE_SEARCH_URL}?${params}`, {
    headers: {
      Accept: "application/json",
      "Accept-Encoding": "gzip",
      "X-Subscription-Token": braveKey,
    },
    signal,
  });
  if (!res.ok) {
    throw new Error(`Brave Search failed (${res.status}): ${await res.text()}`);
  }
  const data = await res.json();
  return (data.web?.results ?? []).map((r: any) => ({
    title: r.title ?? "",
    url: r.url ?? "",
    description: r.description ?? "",
    age: r.age,
  }));
}

async function fetchPageContent(
  url: string,
  signal?: AbortSignal
): Promise<string> {
  const res = await fetch(url, {
    headers: {
      "User-Agent":
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
      Accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    },
    signal,
    redirect: "follow",
  });
  if (!res.ok) {
    throw new Error(`Failed to fetch ${url} (${res.status})`);
  }
  const html = await res.text();
  return htmlToText(html);
}

function htmlToText(html: string): string {
  let text = html;
  text = text.replace(/<script[\s\S]*?<\/script>/gi, "");
  text = text.replace(/<style[\s\S]*?<\/style>/gi, "");
  text = text.replace(/<nav[\s\S]*?<\/nav>/gi, "");
  text = text.replace(/<footer[\s\S]*?<\/footer>/gi, "");
  text = text.replace(/<header[\s\S]*?<\/header>/gi, "");
  text = text.replace(/<!--[\s\S]*?-->/g, "");
  text = text.replace(/<br\s*\/?>/gi, "\n");
  text = text.replace(/<\/p>/gi, "\n\n");
  text = text.replace(/<\/div>/gi, "\n");
  text = text.replace(/<\/li>/gi, "\n");
  text = text.replace(/<\/h[1-6]>/gi, "\n\n");
  text = text.replace(/<[^>]+>/g, "");
  text = text.replace(/&nbsp;/g, " ");
  text = text.replace(/&amp;/g, "&");
  text = text.replace(/&lt;/g, "<");
  text = text.replace(/&gt;/g, ">");
  text = text.replace(/&quot;/g, '"');
  text = text.replace(/&#39;/g, "'");
  text = text.replace(/\n{3,}/g, "\n\n");
  text = text.replace(/[ \t]+/g, " ");
  return text.trim();
}

async function filterWithLLM(
  pageContent: string,
  query: string,
  fireworksKey: string,
  signal?: AbortSignal
): Promise<string> {
  const truncated = pageContent.slice(0, 60_000);

  const res = await fetch(FIREWORKS_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${fireworksKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: FILTER_MODEL,
      messages: [
        {
          role: "system",
          content: `You are a content extraction assistant. Given a web page's text content and a search query, extract ONLY the parts of the page that are directly relevant to answering the query. Rules:
- Return the relevant text verbatim — do not summarize, paraphrase, or add commentary.
- Preserve code blocks, tables, lists, and structured data exactly as they appear.
- Include surrounding context (a sentence or two) so extracted passages make sense on their own.
- If multiple sections are relevant, include all of them separated by "---".
- If nothing on the page is relevant, respond with: "No relevant content found."
- Keep your output under 4000 tokens.`,
        },
        {
          role: "user",
          content: `Search query: "${query}"\n\nPage content:\n${truncated}`,
        },
      ],
      max_tokens: 4096,
      temperature: 0,
    }),
    signal,
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Fireworks API failed (${res.status}): ${errText}`);
  }

  const data = await res.json();
  return data.choices?.[0]?.message?.content ?? "No content extracted.";
}

function formatResults(results: BraveResult[]): string {
  return results
    .map(
      (r, i) =>
        `${i + 1}. [${r.title}](${r.url})${r.age ? ` (${r.age})` : ""}\n   ${r.description}`
    )
    .join("\n\n");
}

function truncateToLimit(text: string): string {
  const result = truncateHead(text, {
    maxLines: DEFAULT_MAX_LINES,
    maxBytes: DEFAULT_MAX_BYTES,
  });

  if (result.truncated) {
    return (
      result.content +
      `\n\n[Output truncated: ${result.outputLines} of ${result.totalLines} lines]`
    );
  }
  return result.content;
}

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: "web_search",
    label: "Web Search",
    description: `Search the web using Brave Search. Returns a list of results with titles, URLs, and snippets. Use this to find relevant pages, then use web_read to extract detailed content from specific URLs.`,
    promptSnippet: "Search the web for current information and return ranked results with URLs, titles, and snippets",
    promptGuidelines: [
      "Use web_search when the user asks about current events, APIs, libraries, tools, or any topic that may have changed since the training data cutoff.",
      "Use web_search before web_read — search first, then read specific pages.",
    ],
    parameters: Type.Object({
      query: Type.String({ description: "The search query" }),
      count: Type.Optional(
        Type.Number({
          description: "Number of results to return (default 8, max 20)",
          minimum: 1,
          maximum: 20,
        })
      ),
    }),
    async execute(toolCallId, params, signal, onUpdate, ctx) {
      const braveKey = await ensureKey(
        "brave",
        "BRAVE_API_KEY",
        "https://api-dashboard.search.brave.com/register",
        ctx
      );

      const count = params.count ?? 8;
      const results = await braveSearch(params.query, braveKey, count, signal);

      if (results.length === 0) {
        return {
          content: [{ type: "text" as const, text: "No results found." }],
        };
      }

      const formatted = formatResults(results);
      const text = `Found ${results.length} results for "${params.query}":\n\n${formatted}`;

      return {
        content: [{ type: "text" as const, text: truncateToLimit(text) }],
        details: { results },
      };
    },
  });

  pi.registerTool({
    name: "web_read",
    label: "Web Read",
    description: `Fetch a web page and extract only the content relevant to your query. The page is fetched, cleaned of HTML, and then filtered through an LLM that extracts only the passages that answer your query — keeping context lean. Use this after web_search to read specific pages.`,
    promptSnippet: "Fetch a web page and extract content relevant to a specific query via an LLM filter",
    promptGuidelines: [
      "Use web_read after web_search to extract detailed content from specific URLs.",
      "Be specific with the query parameter — it drives what content the LLM extracts from the page.",
      "Use web_read when the user needs code examples, documentation, or detailed information from a specific URL.",
    ],
    parameters: Type.Object({
      url: Type.String({ description: "URL to fetch" }),
      query: Type.String({
        description:
          "What you're looking for on this page. Be specific — this drives the content filtering.",
      }),
    }),
    async execute(toolCallId, params, signal, onUpdate, ctx) {
      const fireworksKey = await ensureKey(
        "fireworks",
        "FIREWORKS_API_KEY",
        "https://fireworks.ai",
        ctx
      );

      onUpdate?.({
        content: [{ type: "text", text: `Fetching ${params.url}...` }],
      });
      const pageContent = await fetchPageContent(params.url, signal);

      onUpdate?.({
        content: [{ type: "text", text: "Filtering content with LLM..." }],
      });
      const filtered = await filterWithLLM(
        pageContent,
        params.query,
        fireworksKey,
        signal
      );

      const text = `Relevant content from ${params.url}:\n\n${filtered}`;

      return {
        content: [{ type: "text" as const, text: truncateToLimit(text) }],
        details: {
          url: params.url,
          query: params.query,
          rawLength: pageContent.length,
          filteredLength: filtered.length,
        },
      };
    },
  });
}
