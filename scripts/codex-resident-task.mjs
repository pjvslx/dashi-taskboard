import { createHash } from "node:crypto";

function normalizedRepositoryPath(projectRoot) {
  return projectRoot
    .replace(/\\/g, "/")
    .replace(/\/+$/, "")
    .toLowerCase();
}

export function residentTaskName(projectRoot, port) {
  const repositoryHash = createHash("sha256")
    .update(normalizedRepositoryPath(projectRoot))
    .digest("hex")
    .slice(0, 12);
  return `DashiTaskboard-${repositoryHash}-${port}`;
}

export function residentInjectorArgs({
  injectorPath,
  port,
  attachExisting = false,
  open = false,
}) {
  const args = [injectorPath, "--watch", "--port", String(port)];
  if (open) args.push("--open");
  if (attachExisting) args.push("--attach-existing");
  return args;
}
