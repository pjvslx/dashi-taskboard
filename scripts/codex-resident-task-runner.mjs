#!/usr/bin/env node

import { spawn } from "node:child_process";
import { appendFileSync, mkdirSync } from "node:fs";
import path from "node:path";

function parseArgs(argv) {
  const options = {};
  for (let index = 0; index < argv.length; index += 1) {
    const key = argv[index];
    const value = argv[index + 1];
    if (!key.startsWith("--") || value === undefined) continue;
    options[key.slice(2)] = value;
    index += 1;
  }
  return options;
}

const options = parseArgs(process.argv.slice(2));
const preferredPort = Number(options["preferred-port"] || options.port || 9231);
const projectRoot = path.resolve(options["project-root"] || process.cwd());
const nodePath = options["node-path"] || process.execPath;
const logPath = path.resolve(
  options["log-path"] || path.join(projectRoot, ".data", "logs", "start-codex-taskboard.log"),
);
const injectorPath = path.join(projectRoot, "scripts", "codex-injector.mjs");
const serverPath = path.join(projectRoot, "server", "index.mjs");
const taskboardHealthUrl = "http://127.0.0.1:47823/health";

function log(label, detail = "") {
  try {
    mkdirSync(path.dirname(logPath), { recursive: true });
    appendFileSync(
      logPath,
      `[${new Date().toISOString()}] ${label}${detail ? ` ${detail}` : ""}\n`,
      "utf8",
    );
  } catch (_) {}
}

if (!Number.isInteger(preferredPort) || preferredPort < 1 || preferredPort > 65_535) {
  log("resident-invalid-port", String(options["preferred-port"] || options.port || ""));
  process.exit(2);
}

const sleep = (delayMs) => new Promise((resolve) => setTimeout(resolve, delayMs));

async function fetchJson(url) {
  const response = await fetch(url, { signal: AbortSignal.timeout(1_500) });
  if (!response.ok) throw new Error(`${response.status} ${response.statusText}`);
  return response.json();
}

async function taskboardIsHealthy() {
  try {
    await fetchJson(taskboardHealthUrl);
    return true;
  } catch {
    return false;
  }
}

function candidatePorts() {
  return [...new Set([
    preferredPort,
    9229,
    ...Array.from({ length: 21 }, (_, index) => 9231 + index),
  ])];
}

async function isCodexPort(port) {
  try {
    const targets = await fetchJson(`http://127.0.0.1:${port}/json/list`);
    return Array.isArray(targets) && targets.some((target) => (
      target?.type === "page"
      && (target.url?.startsWith("app://") || target.title === "Codex")
    ));
  } catch {
    return false;
  }
}

async function findCodexPort() {
  const ports = candidatePorts();
  const results = await Promise.all(ports.map(async (port) => (
    (await isCodexPort(port)) ? port : null
  )));
  return results.find((port) => port !== null) ?? null;
}

function pipeOutput(child) {
  child.stdout?.on("data", (chunk) => {
    try { appendFileSync(logPath, chunk); } catch (_) {}
  });
  child.stderr?.on("data", (chunk) => {
    try { appendFileSync(logPath, chunk); } catch (_) {}
  });
}

function spawnHidden(args) {
  const child = spawn(nodePath, args, {
    cwd: projectRoot,
    env: {
      ...process.env,
      CODEX_TASKBOARD_HOST: "127.0.0.1",
    },
    stdio: ["ignore", "pipe", "pipe"],
    windowsHide: true,
  });
  pipeOutput(child);
  return child;
}

let server = null;
let injector = null;
let injectorPort = null;
let stopping = false;
let waitingForCodexLogged = false;

async function ensureTaskboard() {
  if (await taskboardIsHealthy()) return;
  if (!server || server.exitCode !== null || server.killed) {
    server = spawnHidden([serverPath]);
    const started = server;
    log("resident-server-start", `pid=${started.pid}`);
    started.on("error", (error) => log("resident-server-error", error.stack || error.message));
    started.on("exit", (code, signal) => {
      log("resident-server-exit", `pid=${started.pid} code=${code ?? "null"} signal=${signal ?? "none"}`);
      if (server === started) server = null;
    });
  }

  const deadline = Date.now() + 10_000;
  while (!stopping && Date.now() < deadline) {
    if (await taskboardIsHealthy()) return;
    if (server && (server.exitCode !== null || server.killed)) break;
    await sleep(250);
  }
  throw new Error("Taskboard service did not become healthy");
}

function stopInjector(reason) {
  if (!injector || injector.exitCode !== null || injector.killed) return;
  log("resident-injector-stop", `pid=${injector.pid} port=${injectorPort} reason=${reason}`);
  injector.kill("SIGTERM");
}

function startInjector(port) {
  injector = spawnHidden([
    injectorPath,
    "--watch",
    "--port",
    String(port),
    "--attach-existing",
  ]);
  injectorPort = port;
  const started = injector;
  log("resident-injector-start", `pid=${started.pid} port=${port}`);
  started.on("error", (error) => log("resident-injector-error", error.stack || error.message));
  started.on("exit", (code, signal) => {
    log("resident-injector-exit", `pid=${started.pid} port=${port} code=${code ?? "null"} signal=${signal ?? "none"}`);
    if (injector === started) {
      injector = null;
      injectorPort = null;
    }
  });
}

function stop(signal) {
  if (stopping) return;
  stopping = true;
  log("resident-stop", `signal=${signal}`);
  stopInjector(signal);
  if (server?.exitCode === null && !server.killed) server.kill("SIGTERM");
}

for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"]) {
  process.once(signal, () => stop(signal));
}

process.on("uncaughtExceptionMonitor", (error) => {
  log("resident-uncaught-exception", error.stack || error.message);
});
process.on("unhandledRejection", (reason) => {
  log("resident-unhandled-rejection", reason instanceof Error ? reason.stack : String(reason));
});

async function main() {
  log("resident-start", `pid=${process.pid} preferredPort=${preferredPort} node=${nodePath}`);
  let idleDelayMs = 2_000;
  let missedCodexChecks = 0;

  while (!stopping) {
    await ensureTaskboard();
    const activePort = await findCodexPort();

    if (activePort === null) {
      missedCodexChecks += 1;
      if (injector && missedCodexChecks < 3) {
        log("resident-codex-check-missed", `count=${missedCodexChecks} port=${injectorPort}`);
        await sleep(5_000);
        continue;
      }
      stopInjector("codex-unavailable");
      if (!waitingForCodexLogged) {
        log("resident-waiting-for-codex", `preferredPort=${preferredPort}`);
        waitingForCodexLogged = true;
      }
      await sleep(idleDelayMs);
      idleDelayMs = Math.min(idleDelayMs * 2, 30_000);
      continue;
    }

    waitingForCodexLogged = false;
    missedCodexChecks = 0;
    idleDelayMs = 2_000;
    if (!injector || injector.exitCode !== null || injector.killed || injectorPort !== activePort) {
      if (injectorPort !== null && injectorPort !== activePort) {
        stopInjector(`port-changed-to-${activePort}`);
        await sleep(500);
      }
      startInjector(activePort);
    }
    await sleep(5_000);
  }
}

main().catch((error) => {
  log("resident-fatal", error.stack || error.message);
  process.exitCode = 1;
});
