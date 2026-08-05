import { existsSync } from "node:fs";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const npmExecutable = process.platform === "win32" ? "npm.cmd" : "npm";
const viteExecutable = path.join(
  projectRoot,
  "node_modules",
  ".bin",
  process.platform === "win32" ? "vite.cmd" : "vite",
);
const indexHtml = path.join(projectRoot, "dist", "web", "index.html");

function run(command, args) {
  const result = spawnSync(command, args, {
    cwd: projectRoot,
    stdio: "inherit",
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

if (!existsSync(viteExecutable)) {
  run(npmExecutable, ["ci"]);
}

if (!existsSync(indexHtml)) {
  run(npmExecutable, ["run", "build:web"]);
}
