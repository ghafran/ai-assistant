import { createServer } from "node:http";
import { runTask } from "./orchestrator.ts";
import type { EmittedTask } from "./types.ts";

const PORT = Number(process.env.PORT ?? 8787);

/**
 * The single endpoint the phone calls. POST /tasks with the EmittedTask JSON the
 * iOS app writes to its outbox; get back what the agent did.
 */
const server = createServer((req, res) => {
  if (req.method !== "POST" || req.url !== "/tasks") {
    res.writeHead(404, { "content-type": "application/json" });
    res.end(JSON.stringify({ error: "POST /tasks" }));
    return;
  }

  let body = "";
  req.on("data", (chunk) => (body += chunk));
  req.on("end", async () => {
    try {
      const task = JSON.parse(body) as EmittedTask;
      const result = await runTask(task);
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify(result, null, 2));
    } catch (err) {
      res.writeHead(500, { "content-type": "application/json" });
      res.end(JSON.stringify({ error: String(err) }));
    }
  });
});

server.listen(PORT, () => {
  console.log(`Ambient agent orchestrator listening on http://localhost:${PORT}/tasks`);
});
