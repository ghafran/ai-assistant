import { runTask } from "./orchestrator.ts";
import type { EmittedTask } from "./types.ts";

// The two flows from the original vision, as the phone would emit them.
const tasks: EmittedTask[] = [
  {
    spec: {
      intent: "send_message",
      summary: "Tell Greg I'll be 15 minutes late to our meeting.",
      recipient: "g",
      messageBody: "Running ~15 min late to our meeting — sorry!",
      needsClarification: false,
      confidence: 0.93,
    },
    resolvedPhone: "+15551234567",
    createdAt: new Date().toISOString(),
  },
  {
    spec: {
      intent: "book_travel",
      summary: "Find the cheapest weekend trip to Florida.",
      destination: "Florida",
      timeframe: "this weekend",
      needsClarification: false,
      confidence: 0.9,
    },
    createdAt: new Date().toISOString(),
  },
];

for (const task of tasks) {
  console.log("\n=== TaskSpec:", task.spec.summary, "===");
  const result = await runTask(task);
  console.log("Reply:", result.reply);
  console.log("Actions:");
  for (const a of result.actions) {
    console.log(`  • ${a.tool} (${a.detail})`);
  }
}
