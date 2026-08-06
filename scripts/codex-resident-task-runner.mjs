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
const port = Number(options.port);
const projectRoot = path.resolve(options["project-root"] || process.cwd());
const nodePath = options["node-path"] || process.execPath;
const logPath = path.resolve(
  options["log-path"] || path.join(projectRoot, ".data", "logs", "start-codex-taskboard.log"),
);
const injectorPath = path.join(projectRoot, "scripts", "codex-injector.mjs");

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

if (!Number.isInteger(port) || port < 1 || port > 65_535) {
  log("resident-invalid-port", String(options.port || ""));
  process.exit(2);
}

log("resident-start", `pid=${process.pid} port=${port} node=${nodePath}`);

let child = null;
let restartTimer = null;
let stopping = false;

function startInjector() {
  child = spawn(nodePath, [
    injectorPath,
    "--watch",
    "--port",
    String(port),
    "--attach-existing",
  ], {
    cwd: projectRoot,
    env: {
      ...process.env,
      CODEX_TASKBOARD_HOST: "127.0.0.1",
    },
    stdio: ["ignore", "pipe", "pipe"],
    windowsHide: true,
  });
  const started = child;

  started.stdout.on("data", (chunk) => {
    try {
      appendFileSync(logPath, chunk);
    } catch (_) {}
  });
  started.stderr.on("data", (chunk) => {
    try {
      appendFileSync(logPath, chunk);
    } catch (_) {}
  });
  started.on("error", (error) => {
    log("resident-child-error", error.stack || error.message);
  });
  started.on("exit", (code, signal) => {
    log("resident-exit", `childPid=${started.pid} code=${code ?? "null"} signal=${signal ?? "none"}`);
    if (child === started) child = null;
    if (stopping) return;
    log("resident-child-restart", `previousPid=${started.pid} delayMs=1000`);
    restartTimer = setTimeout(startInjector, 1_000);
  });
}

startInjector();

function stop(signal) {
  stopping = true;
  log("resident-stop", `signal=${signal}`);
  if (restartTimer) clearTimeout(restartTimer);
  restartTimer = null;
  if (child && !child.killed) child.kill(signal);
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
