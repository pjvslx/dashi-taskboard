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

const child = spawn(nodePath, [
  injectorPath,
  "--watch",
  "--port",
  String(port),
  "--open",
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

child.stdout.on("data", (chunk) => {
  try {
    appendFileSync(logPath, chunk);
  } catch (_) {}
});
child.stderr.on("data", (chunk) => {
  try {
    appendFileSync(logPath, chunk);
  } catch (_) {}
});
child.on("error", (error) => {
  log("resident-child-error", error.stack || error.message);
});
child.on("exit", (code, signal) => {
  log("resident-exit", `childPid=${child.pid} code=${code ?? "null"} signal=${signal ?? "none"}`);
  process.exitCode = Number.isInteger(code) ? code : 1;
});

function stop(signal) {
  log("resident-stop", `signal=${signal}`);
  if (!child.killed) child.kill(signal);
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
