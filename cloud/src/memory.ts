import { readFileSync, writeFileSync, appendFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import type { Action, TaskSpec, UserProfile } from "./types.ts";

const here = dirname(fileURLToPath(import.meta.url));
const dataDir = join(here, "..", "data");

const PROFILE_PATH = join(dataDir, "profile.json");
const EPISODIC_PATH = join(dataDir, "episodic.jsonl");

/**
 * The authoritative user profile. The phone keeps a synced subset; this is the
 * source of truth the cloud agent reads and writes back to.
 */
export function loadProfile(): UserProfile {
  return JSON.parse(readFileSync(PROFILE_PATH, "utf8")) as UserProfile;
}

export function saveProfile(profile: UserProfile): void {
  writeFileSync(PROFILE_PATH, JSON.stringify(profile, null, 2));
}

/**
 * Episodic memory: one line per completed task. Over time this is what lets the
 * assistant say "like the Miami trip you booked last month" and sharpen preferences.
 */
export function recordEpisode(spec: TaskSpec, actions: Action[], reply: string): void {
  const line = JSON.stringify({
    at: new Date().toISOString(),
    intent: spec.intent,
    summary: spec.summary,
    actions,
    reply,
  });
  appendFileSync(EPISODIC_PATH, line + "\n");
}

export function recentEpisodes(limit = 5): string[] {
  if (!existsSync(EPISODIC_PATH)) return [];
  return readFileSync(EPISODIC_PATH, "utf8")
    .trim()
    .split("\n")
    .filter(Boolean)
    .slice(-limit);
}
