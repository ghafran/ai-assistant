import Anthropic from "@anthropic-ai/sdk";

if (!process.env.ANTHROPIC_API_KEY) {
  console.error("Set ANTHROPIC_API_KEY before running (export ANTHROPIC_API_KEY=sk-ant-...).");
}

// Resolves the key from ANTHROPIC_API_KEY (or an `ant auth login` profile).
export const client = new Anthropic();

export const MODEL = "claude-opus-4-8";
