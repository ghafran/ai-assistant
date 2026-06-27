import type Anthropic from "@anthropic-ai/sdk";
import { client, MODEL } from "./client.ts";
import { makeTools } from "./tools.ts";
import { loadProfile, recordEpisode, recentEpisodes } from "./memory.ts";
import type { EmittedTask, RunContext, TaskResult } from "./types.ts";

function systemPrompt(ctx: RunContext): string {
  const p = ctx.profile;
  const contacts = Object.entries(p.contacts)
    .map(([alias, c]) => `  - "${alias}" -> ${c.name}`)
    .join("\n");
  const episodes = recentEpisodes();
  return [
    "You are the execution layer of an ambient voice assistant. The user spoke a short request,",
    "the phone turned it into a TaskSpec, and your job is to ACTUALLY CARRY IT OUT using the tools.",
    "",
    "Principles:",
    "- Use tools to do real work; do not claim something is done unless a tool confirmed it.",
    "- To message someone, resolve their phone, then DRAFT it with draft_message — the phone",
    "  shows the native Messages sheet for the user to send. Never say you sent it; say you drafted it.",
    "- Ground vague references ('our meeting', 'this weekend') against the calendar/profile.",
    "- For travel, optimize for the user's budget preference unless told otherwise.",
    "- End with one short sentence the assistant can read back to the user describing what you did.",
    "",
    `User: ${p.displayName} | home airport ${p.homeAirport} | budget: ${p.budgetTier}`,
    "Known contact aliases:",
    contacts || "  (none)",
    episodes.length ? "\nRecent activity (for continuity):\n" + episodes.join("\n") : "",
  ].join("\n");
}

function userPrompt(task: EmittedTask): string {
  return [
    "Execute this TaskSpec from the phone:",
    JSON.stringify(task.spec, null, 2),
    task.resolvedPhone ? `\nPhone already resolved on-device: ${task.resolvedPhone}` : "",
  ].join("\n");
}

export async function runTask(task: EmittedTask): Promise<TaskResult> {
  const ctx: RunContext = { profile: loadProfile(), actions: [] };

  // The tool runner drives the full call -> tool -> result -> repeat loop for us.
  const finalMessage = await client.beta.messages.toolRunner({
    model: MODEL,
    max_tokens: 16000,
    thinking: { type: "adaptive" },
    system: systemPrompt(ctx),
    tools: makeTools(ctx),
    messages: [{ role: "user", content: userPrompt(task) }],
  });

  const reply = finalMessage.content
    .filter((b): b is Anthropic.Beta.BetaTextBlock => b.type === "text")
    .map((b) => b.text)
    .join("\n")
    .trim();

  // Surface a drafted message so the phone can present the native compose sheet.
  const draft = ctx.actions.find((a) => a.tool === "draft_message")?.result as
    | { toName: string; toPhone: string; body: string }
    | undefined;

  recordEpisode(task.spec, ctx.actions, reply);
  return { reply, actions: ctx.actions, compose: draft };
}
