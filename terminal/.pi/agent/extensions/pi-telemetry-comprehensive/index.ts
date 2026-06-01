import type { ExtensionAPI, ExtensionContext } from "@mariozechner/pi-coding-agent";
import type { Langfuse as LangfuseType } from "langfuse";
import { mkdir, writeFile, appendFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { homedir } from "node:os";
import { execSync, spawn } from "node:child_process";

// --- Configuration ---
const TELEMETRY_DIR = process.env.PI_TELEMETRY_DIR ?? join(homedir(), ".pi/agent/telemetry");
const PASS_ENTRY = "langfuse/pi-telemetry";

// --- Pass Integration ---
function passExists(entry: string): boolean {
  try {
    execSync(`pass show ${entry} > /dev/null 2>&1`, { stdio: "pipe" });
    return true;
  } catch {
    return false;
  }
}

function passGet(entry: string, field: string): string | null {
  try {
    const output = execSync(`pass show ${entry}`, { encoding: "utf8", stdio: "pipe" });
    const lines = output.split("\n");
    // First line is password, rest are key: value pairs
    for (const line of lines.slice(1)) {
      const match = line.match(new RegExp(`^${field}:\\s*(.+)$`));
      if (match) return match[1].trim();
    }
    return null;
  } catch {
    return null;
  }
}

async function passSet(entry: string, password: string, fields: Record<string, string>): Promise<boolean> {
  return new Promise((resolve) => {
    const content = [password, ...Object.entries(fields).map(([k, v]) => `${k}: ${v}`)].join("\n") + "\n";
    const child = spawn("pass", ["insert", "-m", "-f", entry], { stdio: "pipe" });
    child.stdin.write(content);
    child.stdin.end();
    child.on("close", (code) => resolve(code === 0));
  });
}

async function getLangfuseCredentials(ctx: ExtensionContext, forcePrompt = false): Promise<{ pk: string | null; sk: string | null; baseUrl: string | null }> {
  if (!forcePrompt) {
    // 1. Check env vars first
    const envPk = process.env.LANGFUSE_PUBLIC_KEY;
    const envSk = process.env.LANGFUSE_SECRET_KEY;
    const envBaseUrl = process.env.LANGFUSE_BASEURL;
    if (envPk && envSk) {
      return { pk: envPk, sk: envSk, baseUrl: envBaseUrl ?? null };
    }

    // 2. Check pass
    if (passExists(PASS_ENTRY)) {
      const pk = passGet(PASS_ENTRY, "public_key");
      const sk = passGet(PASS_ENTRY, "secret_key");
      const baseUrl = passGet(PASS_ENTRY, "base_url");
      if (pk && sk) {
        return { pk, sk, baseUrl };
      }
    }
  }

  // 3. Prompt user with "local only" option
  ctx.ui.notify("Langfuse credentials not found. Choose how to proceed.", "warning");

  const choice = await ctx.ui.select("Telemetry backend:", [
    "Langfuse (cloud or self-hosted)",
    "Local files only",
  ]);

  if (!choice || choice === "Local files only") {
    ctx.ui.notify("Running in local-only mode. No data will be sent to Langfuse.", "info");
    return { pk: null, sk: null, baseUrl: null };
  }

  const pk = await ctx.ui.input("Langfuse Public Key:", "pk-lf-...");
  if (!pk) return { pk: null, sk: null, baseUrl: null };

  const sk = await ctx.ui.input("Langfuse Secret Key:", "sk-lf-...");
  if (!sk) return { pk: null, sk: null, baseUrl: null };

  const baseUrl = await ctx.ui.input("Langfuse Base URL (optional, press Enter to skip):", "https://...");

  // 4. Store in pass
  const stored = await passSet(PASS_ENTRY, sk, {
    public_key: pk,
    secret_key: sk,
    ...(baseUrl ? { base_url: baseUrl } : {}),
  });

  if (stored) {
    ctx.ui.notify("Credentials saved to pass.", "success");
  } else {
    ctx.ui.notify("Failed to save credentials to pass. They will be used for this session only.", "warning");
  }

  return { pk, sk, baseUrl: baseUrl || null };
}

// --- Types ---
interface SessionMeta {
  sessionFile: string | null;
  startTime: number;
  model: string;
  provider: string;
  turnCount: number;
  totalInputTokens: number;
  totalOutputTokens: number;
  totalCost: number;
  toolCalls: number;
  toolErrors: number;
  compactions: number;
  modelSwitches: number;
}

interface EventRecord {
  ts: number;
  sessionId: string;
  event: string;
  data: Record<string, unknown>;
}

// --- State (per extension instance) ---
let langfuse: LangfuseType | null = null;
let langfuseModule: typeof import("langfuse") | null = null;
let currentTraceId: string | null = null;
let currentTurnSpanId: string | null = null;
let currentTurnStartTime: number | null = null;
let sessionMeta: SessionMeta | null = null;
let eventBuffer: EventRecord[] = [];
let flushTimer: NodeJS.Timeout | null = null;
const FLUSH_INTERVAL_MS = 2000;
const BUFFER_MAX = 100;

// --- Helpers ---
function generateId(): string {
  return `${Date.now()}-${Math.random().toString(36).slice(2, 11)}`;
}

function getSessionId(ctx: ExtensionContext): string {
  const file = ctx.sessionManager.getSessionFile();
  return file ?? `ephemeral-${generateId()}`;
}

function now(): number {
  return Date.now();
}

async function ensureDir(path: string) {
  if (!existsSync(path)) {
    await mkdir(path, { recursive: true });
  }
}

function getLocalPath(sessionId: string, suffix: string): string {
  // Sanitize session ID for filesystem
  const safe = sessionId.replace(/[^a-zA-Z0-9._-]/g, "_");
  return join(TELEMETRY_DIR, `${safe}${suffix}`);
}

async function flushEvents() {
  if (eventBuffer.length === 0) return;
  const batch = eventBuffer.splice(0, eventBuffer.length);
  if (batch.length === 0) return;

  const sessionId = batch[0].sessionId;
  const path = getLocalPath(sessionId, ".jsonl");
  await ensureDir(dirname(path));

  const lines = batch.map((e) => JSON.stringify(e)).join("\n") + "\n";
  await appendFile(path, lines, "utf8");
}

function queueEvent(sessionId: string, event: string, data: Record<string, unknown>) {
  eventBuffer.push({ ts: now(), sessionId, event, data });
  if (eventBuffer.length >= BUFFER_MAX) {
    flushEvents().catch(() => {});
  }
}

function startFlushTimer() {
  if (flushTimer) return;
  flushTimer = setInterval(() => {
    flushEvents().catch(() => {});
  }, FLUSH_INTERVAL_MS);
}

function stopFlushTimer() {
  if (flushTimer) {
    clearInterval(flushTimer);
    flushTimer = null;
  }
}

// --- Langfuse Integration ---
async function initLangfuse(pk: string, sk: string, baseUrl: string | null): Promise<LangfuseType | null> {
  try {
    if (!langfuseModule) {
      langfuseModule = await import("langfuse");
    }
    const LangfuseCtor = langfuseModule?.Langfuse ?? (langfuseModule as any)?.default;
    if (!LangfuseCtor) {
      return null;
    }
    return new LangfuseCtor({
      publicKey: pk,
      secretKey: sk,
      baseUrl: baseUrl ?? undefined,
    });
  } catch {
    return null;
  }
}

// --- Extension Factory ---
export default async function (pi: ExtensionAPI) {
  // Credentials resolved lazily in session_start

  // --- Session Lifecycle ---
  pi.on("session_start", async (event, ctx) => {
    const sessionId = getSessionId(ctx);

    // Resolve Langfuse credentials on first session start
    if (!langfuse) {
      const creds = await getLangfuseCredentials(ctx);
      if (creds.pk && creds.sk) {
        langfuse = await initLangfuse(creds.pk, creds.sk, creds.baseUrl);
        if (langfuse) {
          ctx.ui.notify("Langfuse telemetry enabled.", "info");
        }
      }
    }

    const model = ctx.model;
    const modelName = model ? `${model.provider}/${model.id}` : "unknown";

    sessionMeta = {
      sessionFile: ctx.sessionManager.getSessionFile(),
      startTime: now(),
      model: modelName,
      provider: model?.provider ?? "unknown",
      turnCount: 0,
      totalInputTokens: 0,
      totalOutputTokens: 0,
      totalCost: 0,
      toolCalls: 0,
      toolErrors: 0,
      compactions: 0,
      modelSwitches: 0,
    };

    currentTraceId = generateId();

    queueEvent(sessionId, "session_start", {
      reason: event.reason,
      previousSessionFile: event.previousSessionFile,
      model: modelName,
      cwd: ctx.cwd,
    });

    if (langfuse) {
      langfuse.trace({
        id: currentTraceId,
        name: "pi-session",
        metadata: {
          reason: event.reason,
          cwd: ctx.cwd,
          model: modelName,
        },
      });
    }

    startFlushTimer();
  });

  pi.on("session_shutdown", async (event, ctx) => {
    const sessionId = getSessionId(ctx);
    const duration = sessionMeta ? now() - sessionMeta.startTime : 0;

    queueEvent(sessionId, "session_shutdown", {
      reason: event.reason,
      durationMs: duration,
      ...sessionMeta,
    });

    await flushEvents();
    stopFlushTimer();

    if (langfuse && currentTraceId) {
      langfuse.score({
        traceId: currentTraceId,
        name: "session_summary",
        value: sessionMeta?.turnCount ?? 0,
        comment: `Turns: ${sessionMeta?.turnCount}, Tools: ${sessionMeta?.toolCalls}, Errors: ${sessionMeta?.toolErrors}, Cost: $${(sessionMeta?.totalCost ?? 0).toFixed(4)}`,
      });
    }

    sessionMeta = null;
    currentTraceId = null;
    currentTurnSpanId = null;
  });

  // --- Model Events ---
  pi.on("model_select", async (event, ctx) => {
    const sessionId = getSessionId(ctx);
    const prev = event.previousModel ? `${event.previousModel.provider}/${event.previousModel.id}` : "none";
    const next = `${event.model.provider}/${event.model.id}`;

    if (sessionMeta) sessionMeta.modelSwitches++;

    queueEvent(sessionId, "model_select", {
      source: event.source,
      previous: prev,
      next,
    });

    if (langfuse && currentTraceId) {
      langfuse.span({
        traceId: currentTraceId,
        name: "model_switch",
        metadata: { from: prev, to: next, source: event.source },
      });
    }
  });

  pi.on("thinking_level_select", async (event, ctx) => {
    const sessionId = getSessionId(ctx);
    queueEvent(sessionId, "thinking_level_select", {
      level: event.level,
      previousLevel: event.previousLevel,
    });
  });

  // --- Agent / Turn Events ---
  pi.on("agent_start", async (_event, ctx) => {
    // nothing extra beyond turn tracking
  });

  pi.on("turn_start", async (event, ctx) => {
    const sessionId = getSessionId(ctx);
    if (sessionMeta) sessionMeta.turnCount++;

    currentTurnSpanId = generateId();
    currentTurnStartTime = event.timestamp;

    queueEvent(sessionId, "turn_start", {
      turnIndex: event.turnIndex,
      timestamp: event.timestamp,
    });
  });

  pi.on("turn_end", async (event, ctx) => {
    const sessionId = getSessionId(ctx);
    queueEvent(sessionId, "turn_end", {
      turnIndex: event.turnIndex,
      toolResultCount: event.toolResults?.length ?? 0,
    });

    if (langfuse && currentTraceId && currentTurnSpanId && currentTurnStartTime) {
      langfuse.span({
        traceId: currentTraceId,
        id: currentTurnSpanId,
        name: `turn_${event.turnIndex}`,
        startTime: new Date(currentTurnStartTime),
        endTime: new Date(),
      });
    }
    currentTurnSpanId = null;
    currentTurnStartTime = null;
  });

  // --- Message Events ---
  pi.on("message_start", async (event, ctx) => {
    const sessionId = getSessionId(ctx);
    queueEvent(sessionId, "message_start", {
      role: event.message.role,
      messageId: event.message.id,
    });
  });

  pi.on("message_end", async (event, ctx) => {
    const sessionId = getSessionId(ctx);
    const msg = event.message;

    if (msg.role === "assistant" && msg.usage) {
      const u = msg.usage;
      const inputTokens = u.inputTokens ?? 0;
      const outputTokens = u.outputTokens ?? 0;
      const cost = u.cost?.total ?? 0;

      if (sessionMeta) {
        sessionMeta.totalInputTokens += inputTokens;
        sessionMeta.totalOutputTokens += outputTokens;
        sessionMeta.totalCost += cost;
      }

      queueEvent(sessionId, "message_end", {
        role: msg.role,
        messageId: msg.id,
        inputTokens,
        outputTokens,
        cost,
        model: msg.model,
      });

      if (langfuse && currentTraceId && currentTurnSpanId) {
        langfuse.generation({
          traceId: currentTraceId,
          parentObservationId: currentTurnSpanId,
          name: "llm_generation",
          model: msg.model ?? sessionMeta?.model,
          usage: {
            input: inputTokens,
            output: outputTokens,
            total: inputTokens + outputTokens,
          },
          metadata: { cost },
        });
      }
    } else {
      queueEvent(sessionId, "message_end", {
        role: msg.role,
        messageId: msg.id,
      });
    }
  });

  // --- Tool Events ---
  pi.on("tool_execution_start", async (event, ctx) => {
    const sessionId = getSessionId(ctx);
    if (sessionMeta) sessionMeta.toolCalls++;

    queueEvent(sessionId, "tool_execution_start", {
      toolCallId: event.toolCallId,
      toolName: event.toolName,
      args: event.args,
    });
  });

  pi.on("tool_execution_end", async (event, ctx) => {
    const sessionId = getSessionId(ctx);
    if (event.isError && sessionMeta) sessionMeta.toolErrors++;

    queueEvent(sessionId, "tool_execution_end", {
      toolCallId: event.toolCallId,
      toolName: event.toolName,
      isError: event.isError,
    });

    if (langfuse && currentTraceId && currentTurnSpanId) {
      langfuse.span({
        traceId: currentTraceId,
        parentObservationId: currentTurnSpanId,
        name: event.toolName,
        metadata: { toolCallId: event.toolCallId, isError: event.isError },
      });
    }
  });

  // --- Compaction Events ---
  pi.on("session_compact", async (event, ctx) => {
    const sessionId = getSessionId(ctx);
    if (sessionMeta) sessionMeta.compactions++;

    queueEvent(sessionId, "session_compact", {
      fromExtension: event.fromExtension,
    });
  });

  // --- Tree / Fork Events ---
  pi.on("session_tree", async (event, ctx) => {
    const sessionId = getSessionId(ctx);
    queueEvent(sessionId, "session_tree", {
      newLeafId: event.newLeafId,
      oldLeafId: event.oldLeafId,
    });
  });

  pi.on("session_before_fork", async (event, ctx) => {
    const sessionId = getSessionId(ctx);
    queueEvent(sessionId, "session_before_fork", {
      entryId: event.entryId,
      position: event.position,
    });
  });

  // --- Input Events ---
  pi.on("input", async (event, ctx) => {
    const sessionId = getSessionId(ctx);
    queueEvent(sessionId, "input", {
      source: event.source,
      textLength: event.text?.length ?? 0,
      hasImages: (event.images?.length ?? 0) > 0,
    });
  });

  // --- Provider Events ---
  pi.on("before_provider_request", async (event, ctx) => {
    const sessionId = getSessionId(ctx);
    queueEvent(sessionId, "before_provider_request", {
      model: event.payload.model,
      timestamp: now(),
    });
  });

  pi.on("after_provider_response", async (event, ctx) => {
    const sessionId = getSessionId(ctx);
    queueEvent(sessionId, "after_provider_response", {
      status: event.status,
      timestamp: now(),
    });
  });

  // --- Commands ---
  pi.registerCommand("telemetry", {
    description: "Show current session telemetry summary",
    handler: async (_args, ctx) => {
      if (!sessionMeta) {
        ctx.ui.notify("No active session telemetry", "warning");
        return;
      }
      const duration = now() - sessionMeta.startTime;
      const lines = [
        `Session: ${sessionMeta.sessionFile ?? "ephemeral"}`,
        `Duration: ${(duration / 1000).toFixed(1)}s`,
        `Turns: ${sessionMeta.turnCount}`,
        `Model: ${sessionMeta.model}`,
        `Tokens: ${sessionMeta.totalInputTokens} in / ${sessionMeta.totalOutputTokens} out`,
        `Cost: $${sessionMeta.totalCost.toFixed(4)}`,
        `Tools: ${sessionMeta.toolCalls} calls, ${sessionMeta.toolErrors} errors`,
        `Compactions: ${sessionMeta.compactions}`,
        `Model switches: ${sessionMeta.modelSwitches}`,
      ];
      ctx.ui.notify(lines.join(" | "), "info");
    },
  });

  pi.registerCommand("telemetry-export", {
    description: "Export current session telemetry to a JSON file",
    handler: async (_args, ctx) => {
      const sessionId = getSessionId(ctx);
      const path = getLocalPath(sessionId, ".json");
      await ensureDir(dirname(path));

      const entries = ctx.sessionManager.getEntries();
      const exportData = {
        sessionId,
        meta: sessionMeta,
        entryCount: entries.length,
        exportedAt: now(),
      };
      await writeFile(path, JSON.stringify(exportData, null, 2), "utf8");
      ctx.ui.notify(`Telemetry exported to ${path}`, "success");
    },
  });

  pi.registerCommand("telemetry-reset-keys", {
    description: "Reset Langfuse credentials and re-prompt",
    handler: async (_args, ctx) => {
      // Clear existing Langfuse instance and credentials
      langfuse = null;
      langfuseModule = null;

      // Re-run credential prompt
      const creds = await getLangfuseCredentials(ctx, true);
      if (creds.pk && creds.sk) {
        langfuse = await initLangfuse(creds.pk, creds.sk, creds.baseUrl);
        if (langfuse) {
          ctx.ui.notify("Langfuse credentials updated and telemetry enabled.", "success");
        } else {
          ctx.ui.notify("Failed to initialize Langfuse with new credentials.", "error");
        }
      } else {
        ctx.ui.notify("Running in local-only mode. Credentials cleared.", "info");
      }
    },
  });
}
