import fs from "node:fs";
import http from "node:http";

function argument(name, fallback = "") {
  const index = process.argv.indexOf(name);
  return index >= 0 && index + 1 < process.argv.length ? process.argv[index + 1] : fallback;
}

function requiredEnvironment(name) {
  const value = process.env[name];
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function findPageTarget(port) {
  const deadline = Date.now() + 30_000;
  let lastError = "WebView2 CDP endpoint is not ready";
  while (Date.now() < deadline) {
    try {
      const response = await fetch(`http://127.0.0.1:${port}/json/list`);
      if (response.ok) {
        const targets = await response.json();
        const target = targets.find((item) => item.type === "page" && item.webSocketDebuggerUrl);
        if (target) return target;
      }
    } catch (error) {
      lastError = String(error instanceof Error ? error.message : error);
    }
    await delay(250);
  }
  throw new Error(`Unable to find the manager WebView2 page: ${lastError}`);
}

async function evaluateInManager(port, expression) {
  const target = await findPageTarget(port);
  const socket = new WebSocket(target.webSocketDebuggerUrl);
  const pending = new Map();
  let nextId = 1;

  await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("Timed out connecting to WebView2 CDP")), 10_000);
    socket.addEventListener("open", () => {
      clearTimeout(timeout);
      resolve();
    });
    socket.addEventListener("error", () => {
      clearTimeout(timeout);
      reject(new Error("WebView2 CDP websocket connection failed"));
    });
  });

  socket.addEventListener("message", (event) => {
    const message = JSON.parse(String(event.data));
    if (!message.id || !pending.has(message.id)) return;
    const { resolve, reject } = pending.get(message.id);
    pending.delete(message.id);
    if (message.error) reject(new Error(`CDP command failed: ${message.error.message}`));
    else resolve(message.result);
  });

  const send = (method, params = {}) => new Promise((resolve, reject) => {
    const id = nextId++;
    pending.set(id, { resolve, reject });
    socket.send(JSON.stringify({ id, method, params }));
  });

  try {
    await send("Runtime.enable");
    const result = await send("Runtime.evaluate", {
      expression,
      awaitPromise: true,
      returnByValue: true,
    });
    if (result.exceptionDetails) throw new Error("Manager WebView2 evaluation failed");
    return result.result?.value;
  } finally {
    socket.close();
  }
}

async function clickConfirm(port) {
  const deadline = Date.now() + 30_000;
  while (Date.now() < deadline) {
    const clicked = await evaluateInManager(port, `(() => {
      const button = [...document.querySelectorAll("button")].find((item) =>
        /确认导入|Confirm import/i.test((item.textContent || "").trim())
      );
      if (!button || button.disabled) return false;
      button.click();
      return true;
    })()`);
    if (clicked) {
      process.stdout.write("CDP_CONFIRM_CLICKED\n");
      return;
    }
    await delay(300);
  }
  throw new Error("The provider import confirmation button did not appear");
}

function responseEvents(model) {
  const responseId = "resp_ci_responses";
  const itemId = "msg_ci_responses";
  const usage = {
    input_tokens: 1,
    input_tokens_details: { cached_tokens: 0 },
    output_tokens: 1,
    output_tokens_details: { reasoning_tokens: 0 },
    total_tokens: 2,
  };
  const message = {
    id: itemId,
    type: "message",
    status: "completed",
    role: "assistant",
    content: [{ type: "output_text", text: "CI_OK", annotations: [] }],
  };
  const base = (status, output) => ({
    id: responseId,
    object: "response",
    created_at: Math.floor(Date.now() / 1000),
    status,
    model,
    output,
    usage,
  });
  const events = [
    ["response.created", { type: "response.created", response: base("in_progress", []) }],
    ["response.in_progress", { type: "response.in_progress", response: base("in_progress", []) }],
    ["response.output_item.added", {
      type: "response.output_item.added",
      output_index: 0,
      item: { id: itemId, type: "message", status: "in_progress", role: "assistant", content: [] },
    }],
    ["response.content_part.added", {
      type: "response.content_part.added",
      item_id: itemId,
      output_index: 0,
      content_index: 0,
      part: { type: "output_text", text: "", annotations: [] },
    }],
    ["response.output_text.delta", {
      type: "response.output_text.delta",
      item_id: itemId,
      output_index: 0,
      content_index: 0,
      delta: "CI_OK",
    }],
    ["response.output_text.done", {
      type: "response.output_text.done",
      item_id: itemId,
      output_index: 0,
      content_index: 0,
      text: "CI_OK",
    }],
    ["response.content_part.done", {
      type: "response.content_part.done",
      item_id: itemId,
      output_index: 0,
      content_index: 0,
      part: message.content[0],
    }],
    ["response.output_item.done", { type: "response.output_item.done", output_index: 0, item: message }],
    ["response.completed", { type: "response.completed", response: base("completed", [message]) }],
  ];
  return `${events.map(([event, data]) => `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`).join("")}data: [DONE]\n\n`;
}

function chatEvents(model) {
  const created = Math.floor(Date.now() / 1000);
  const chunks = [
    { id: "chatcmpl_ci", object: "chat.completion.chunk", created, model, choices: [{ index: 0, delta: { role: "assistant", content: "CI_OK" }, finish_reason: null }] },
    { id: "chatcmpl_ci", object: "chat.completion.chunk", created, model, choices: [{ index: 0, delta: {}, finish_reason: "stop" }], usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 } },
  ];
  return `${chunks.map((chunk) => `data: ${JSON.stringify(chunk)}\n\n`).join("")}data: [DONE]\n\n`;
}

function startServer() {
  const port = Number(argument("--port"));
  const capturePath = argument("--capture");
  if (!Number.isInteger(port) || port <= 0 || !capturePath) {
    throw new Error("serve requires --port and --capture");
  }
  const responsesKey = requiredEnvironment("CI_RESPONSES_KEY");
  const chatKey = requiredEnvironment("CI_CHAT_KEY");

  const server = http.createServer((request, response) => {
    const chunks = [];
    request.on("data", (chunk) => chunks.push(chunk));
    request.on("end", () => {
      const url = new URL(request.url || "/", `http://127.0.0.1:${port}`);
      if (url.pathname === "/health") {
        response.writeHead(200, { "content-type": "application/json" });
        response.end('{"ok":true}');
        return;
      }
      if (url.pathname === "/shutdown") {
        response.writeHead(200, { "content-type": "application/json" });
        response.end('{"ok":true}');
        server.close();
        return;
      }

      const authorization = request.headers.authorization || "";
      const responseAuthMatch = authorization === `Bearer ${responsesKey}`;
      const chatAuthMatch = authorization === `Bearer ${chatKey}`;
      let body = {};
      try {
        body = JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}");
      } catch {
        body = {};
      }
      fs.appendFileSync(capturePath, `${JSON.stringify({
        method: request.method,
        path: url.pathname,
        responsesAuthMatch: responseAuthMatch,
        chatAuthMatch,
        model: typeof body.model === "string" ? body.model : "",
        stream: body.stream === true,
        hasInput: Object.hasOwn(body, "input"),
        hasMessages: Array.isArray(body.messages),
      })}\n`);

      if (url.pathname === "/v1/models") {
        if (!responseAuthMatch && !chatAuthMatch) {
          response.writeHead(401, { "content-type": "application/json" });
          response.end('{"error":{"message":"invalid test credential"}}');
          return;
        }
        const model = responseAuthMatch ? "ci-responses-model" : "ci-chat-model";
        response.writeHead(200, { "content-type": "application/json" });
        response.end(JSON.stringify({ object: "list", data: [{ id: model, object: "model", created: 0, owned_by: "ci" }] }));
        return;
      }

      if (url.pathname === "/v1/responses" && responseAuthMatch) {
        response.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-cache", connection: "close" });
        response.end(responseEvents(typeof body.model === "string" ? body.model : "ci-model"));
        return;
      }
      if (url.pathname === "/v1/chat/completions" && chatAuthMatch) {
        response.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-cache", connection: "close" });
        response.end(chatEvents(typeof body.model === "string" ? body.model : "ci-model"));
        return;
      }

      response.writeHead(401, { "content-type": "application/json" });
      response.end('{"error":{"message":"invalid test request"}}');
    });
  });
  server.listen(port, "127.0.0.1", () => process.stdout.write(`MOCK_READY ${port}\n`));
}

const mode = process.argv[2] || "serve";
if (mode === "click-confirm") await clickConfirm(Number(argument("--cdp-port")));
else if (mode === "serve") startServer();
else throw new Error(`Unknown mode: ${mode}`);
