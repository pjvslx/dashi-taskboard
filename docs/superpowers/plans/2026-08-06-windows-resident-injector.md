# Windows Resident Injector Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Keep the Taskboard injector and local service alive after the Codex task that launched them completes.

**Architecture:** A focused PowerShell installer registers and starts a per-port Windows scheduled task. The existing batch launcher calls that installer after Codex CDP becomes ready, while the scheduled task runs the existing injector in watch mode from the repository directory.

**Tech Stack:** Windows Task Scheduler, PowerShell 5.1+, Node.js 22.5+, Node test runner, batch scripting.

## Global Constraints

- Preserve `start-codex-taskboard.bat` as the user-facing entry point.
- Use one scheduled task per repository and debugging port.
- Run the resident injector with no execution time limit.
- Preserve `.data/logs/start-codex-taskboard.log` and `.data/logs/codex-injector.log` diagnostics.
- Do not change Taskboard data, UI, issue automation, or project selection behavior.

---

### Task 1: Scheduled Task Command Model

**Files:**
- Create: `scripts/codex-resident-task.mjs`
- Modify: `test/injector-host-runtime.test.mjs`

**Interfaces:**
- Produces: `residentTaskName(projectRoot, port): string`
- Produces: `residentInjectorArgs({ injectorPath, port, attachExisting, open }): string[]`

- [x] **Step 1: Write the failing tests**

Add tests that require a stable repository-specific task name, separate names for different ports, and arguments containing the absolute injector path plus `--watch`, `--port`, `--open`, and `--attach-existing`.

- [x] **Step 2: Run the tests and verify RED**

Run: `node --test test/injector-host-runtime.test.mjs`
Expected: FAIL because `scripts/codex-resident-task.mjs` does not exist.

- [x] **Step 3: Implement the command model**

Use a SHA-256 prefix of the normalized repository path in the task name. Return argument tokens without shell quoting so the PowerShell installer can quote each token safely.

- [x] **Step 4: Run the tests and verify GREEN**

Run: `node --test test/injector-host-runtime.test.mjs`
Expected: PASS.

- [x] **Step 5: Commit**

```powershell
git add scripts/codex-resident-task.mjs test/injector-host-runtime.test.mjs
git commit -m "test: define Windows resident task command"
```

### Task 2: Independent Windows Hosting

**Files:**
- Create: `scripts/install-codex-resident-task.ps1`
- Create: `scripts/codex-resident-task-runner.mjs`
- Modify: `start-codex-taskboard.bat`
- Modify: `test/injector.test.mjs`

**Interfaces:**
- Installer inputs: `-Port <int>`, `-NodePath <absolute path>`, `-ProjectRoot <absolute path>`, `-LogPath <absolute path>`
- Runner inputs: `--port <int> --project-root <path> --node-path <path>`
- Installer exit code: `0` only after registration and start requests succeed.

- [x] **Step 1: Write the failing launcher tests**

Require the batch launcher to call `install-codex-resident-task.ps1`; require the installer to use `Register-ScheduledTask`, `New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero)`, and `Start-ScheduledTask`; require the runner to append stdout, stderr, startup, and exit details to the launcher log.

- [x] **Step 2: Run the tests and verify RED**

Run: `node --test test/injector.test.mjs`
Expected: FAIL because the installer and runner do not exist and the launcher still uses `codex:daemon`.

- [x] **Step 3: Implement the installer and runner**

The installer must replace any existing definition with the same stable name, configure an interactive-user principal, set restart-on-failure, disable execution timeout, and start the task. The runner must spawn the injector in foreground watch mode and mirror its output to `.data/logs/start-codex-taskboard.log` without swallowing the injector's own diagnostics.

- [x] **Step 4: Update the batch launcher**

Resolve `node.exe`, invoke the installer with absolute repository and log paths, surface nonzero status, and remove the old `npm run codex:daemon` path.

- [x] **Step 5: Run focused tests and verify GREEN**

Run: `node --test test/injector.test.mjs test/injector-host-runtime.test.mjs`
Expected: PASS.

- [x] **Step 6: Verify repository health**

Run: `npm run typecheck`, `npm run build`, and `node --test test/inject.test.mjs test/injector.test.mjs test/injector-host-runtime.test.mjs`.
Expected: all commands exit 0.

- [x] **Step 7: Perform Windows integration verification**

Run `start-codex-taskboard.bat`, confirm the scheduled task is Running, confirm ports 9231 and 47823 listen, and confirm new injector heartbeats continue after the launching command exits.
